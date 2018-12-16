local constants = require 'src/constants'
local generateRound = require 'src/generateRound'
local listHelpers = require 'src/util/list'
local Promise = require 'src/util/Promise'
local Entity = require 'src/entity/Entity'
local PlayButton = require 'src/entity/PlayButton'
local Title = require 'src/entity/Title'
local Hand = require 'src/entity/Hand'
local Card = require 'src/entity/Card'
local Sounds = require 'src/Sounds'
local SpriteSheet = require 'src/util/SpriteSheet'
local RoundResults = require 'src/entity/RoundResults'
local ScoreCalculation = require 'src/entity/ScoreCalculation'
local RoundIndicator = require 'src/entity/RoundIndicator'

-- Scene vars
local scene
local isTransitioningScenes
local initTitleScreen
local transitionToGameplay
local initRoundStart
local transitionToRoundEnd
local initRoundEnd
local roundNumber
local mostRoundsEncountered

-- Entity vars
local entities
local hand
local roundResults
local isGunLoaded = false

-- Render vars
local backgroundCycleX = 0
local backgroundCycleY = 0

-- Spritesheet vars
local SPRITESHEET = SpriteSheet.new('img/ui.png', {
  BACKGROUND = { 1, 140, 42, 22 }
})

-- Render layers
-- 0: background + shadows
-- 3: round results
-- 5: launched cards
-- 7: card explosiotn
-- 8: gunshot
-- 9: cards in hand

-- Entity methods
Entity.spawn = function(class, args)
  local entity = class.new(args)
  table.insert(entities, entity)
  return entity
end

local function removeDeadEntities(list)
  return listHelpers.filter(list, function(entity)
    return entity.isAlive
  end)
end

local function playGunshotSound(isClickInsideGame)
  if isClickInsideGame then
    -- Gunshot
    Sounds.gunshot:play()

    -- A random pew.
    local pew = math.random(1, 12)
    if     pew == 1 then  Sounds.pew1:play()
    elseif pew == 2 then  Sounds.pew2:play()
    elseif pew == 3 then  Sounds.pew3:play()
    elseif pew == 4 then  Sounds.pew4:play()
    elseif pew == 5 then  Sounds.pew5:play()
    elseif pew == 6 then  Sounds.pew6:play()
    elseif pew == 7 then  Sounds.pew7:play()
    elseif pew == 8 then  Sounds.pew8:play()
    elseif pew == 9 then  Sounds.pew9:play()
    elseif pew == 10 then Sounds.pew10:play()
    elseif pew == 11 then Sounds.pew11:play()
    elseif pew == 12 then Sounds.pew12:play()
    end
  else
    -- Empty gun trigger click
    Sounds.gunclick:play()
  end
end

-- Scene methods
initTitleScreen = function()
  scene = 'title'
  roundNumber = 1
  isGunLoaded = true
  Title:spawn({
    x = constants.GAME_MIDDLE_X,
    y = constants.GAME_HEIGHT * 0.35
  })
  local playButton = PlayButton:spawn({
    x = constants.GAME_MIDDLE_X,
    y = constants.GAME_HEIGHT * 0.75,
    onClicked = function(self)
      transitionToGameplay()
    end
  })
  Sounds.titleLoop:play()
  if mostRoundsEncountered > 0 then
    RoundIndicator:spawn({
      scenes = { 'title' },
      roundNumber = mostRoundsEncountered,
      displayBest = true,
      y = playButton.y + 20
    })
  end
end

transitionToGameplay = function()
  if not isTransitioningScenes then
    isTransitioningScenes = true
    Promise.newActive(0)
      :andThen(function()
        isTransitioningScenes = false
        initRoundStart()
      end)
    end
end

initRoundStart = function()
  isGunLoaded = false
  scene = 'round-start'
  mostRoundsEncountered = math.max(mostRoundsEncountered, roundNumber)
  RoundIndicator:spawn({
    roundNumber = roundNumber
  })
  -- Generate a new round
  local round = generateRound(roundNumber)
  -- Create hand of cards
  local cardsInHand = {}
  local index, cardProps
  for index, cardProps in ipairs(round.hand) do
    table.insert(cardsInHand, Card:spawn({
      rankIndex = cardProps.rankIndex,
      suitIndex = cardProps.suitIndex,
      x = constants.GAME_MIDDLE_X,
      y = constants.GAME_TOP - 0.6 * constants.CARD_HEIGHT,
      rotation = math.random(0, 360)
    }))
  end
  hand = Hand:spawn({
    cards = cardsInHand
  })
  -- Create cards that'll be launched into the air
  local cardsInPlay = {}
  for index, cardProps in ipairs(round.cards) do
    table.insert(cardsInPlay, Card:spawn({
      rankIndex = cardProps.rankIndex,
      suitIndex = cardProps.suitIndex,
      x = cardProps.x,
      y = cardProps.y,
      vr = math.random(-80, 80),
      hand = hand
    }))
  end
  -- Loop the music
  -- TODO: loop any music while playing
  Sounds.titleLoop:stop()
  -- Deal hand cards and then launch remaining cards
  Promise.newActive(function()
      Sounds.roundStart:play()
      return hand:dealCards() + 0.6
    end)
    :andThen(function()
      Sounds.handSlide:play()
      return hand:moveToBottom()
    end)
    :andThen(function()
      Sounds.unholster:play()
      return 0.5
    end)
    :andThen(function()
      isGunLoaded = true
      local launchMult = constants.TURBO_MODE and 0.4 or 1.0
      local index, card
      for index, cardProps in ipairs(round.cards) do
        local card = cardsInPlay[index]
        Promise.newActive(launchMult * cardProps.launchDelay):andThen(
          function()
            card.canBeShot = true
            card:launch(2 * (cardProps.apexX - card.x), cardProps.apexY - card.y, launchMult * cardProps.launchDuration)
            -- higher launch == higher pitched sound
            local pitch = 0.7 + 0.6 * (1.0 - (cardProps.apexY / constants.GAME_HEIGHT))
            Sounds.launch:playWithPitch(pitch)
          end)
      end
      return launchMult * round.launchDuration
    end)
    :andThen(function()
      isGunLoaded = false
      Sounds.handSlide:play()
      return hand:moveToCenter() - 1.0
    end)
    :andThen(function()
      return hand:showShotCards()
    end)
    :andThen(function()
      local scoreCalculation = ScoreCalculation:spawn({
        score = hand:getSumValue(),
        x = constants.GAME_MIDDLE_X,
        y = constants.GAME_MIDDLE_Y - constants.CARD_HEIGHT / 2 - 17
      })
      Sounds.scoreCounter:play()
      return Promise.newActive(1.0)
        :andThen(function()
          scoreCalculation:showScore()
        end)
    end)
    :andThen(0.6)
    :andThen(function()
      local value = hand:getSumValue()
      local result
      if value == 21 then
        result = 'blackjack'
        Sounds.blackjack:play()
        playGunshotSound(true)
      elseif value < 21 then
        result = 'miss'
        Sounds.gameOver:play() -- TODO: card explosion/ruffling
      elseif value > 21 then
        result = 'bust'
        Sounds.gameOver:play() -- TODO: card explosion/ruffling
      end
      RoundResults:spawn({
        result = result
      })
      hand:explode(value == 21 and 3 or 1)
    end)
    :andThen(2.0)
    :andThen(function()
      local value = hand:getSumValue()
      entities = {}
      if value == 21 then
        roundNumber = roundNumber + 1
        initRoundStart()
      else
        return Promise.newActive(8.0)
        :andThen(function()
          initTitleScreen()
        end)
      end
    end)
end

transitionToRoundEnd = function()
  if not isTransitioningScenes then
    isTransitioningScenes = true
    Promise.newActive(1)
      :andThen(function()
        isTransitioningScenes = false
        initRoundEnd()
      end)
  end
end

initRoundEnd = function()
  scene = 'round-end'
  local handValue = hand:getSumValue()
  local isWinningHand = (handValue == 21)
  local result
  if handValue == 21 and #hand.cards == 2 then
    result = 'blackjack'
  elseif handValue == 21 then
    result = 'win'
  elseif handValue > 21 then
    result = 'bust'
  else
    result = 'miss'
  end
  roundResults = RoundResults:spawn({
    result = result
  })
  Promise.newActive(1)
    :andThen(function()
      entities = {}
      if isWinningHand then
        -- TODO
      else
        initTitleScreen()
      end
    end)
end

local function initSounds()
  Sounds.gunshot = Sound:new("snd/gunshot.mp3", 8)
  Sounds.gunclick = Sound:new("snd/gun_trigger_empty.wav", 5)
  Sounds.pew1 = Sound:new("snd/pew1.wav", 8)
  Sounds.pew2 = Sound:new("snd/pew2.wav", 8)
  Sounds.pew3 = Sound:new("snd/pew3.wav", 8)
  Sounds.pew4 = Sound:new("snd/pew4.wav", 8)
  Sounds.pew5 = Sound:new("snd/pew5.wav", 8)
  Sounds.pew6 = Sound:new("snd/pew6.wav", 8)
  Sounds.pew7 = Sound:new("snd/pew7.wav", 8)
  Sounds.pew8 = Sound:new("snd/pew8.wav", 8)
  Sounds.pew9 = Sound:new("snd/pew9.wav", 8)
  Sounds.pew10 = Sound:new("snd/pew10.wav", 8)
  Sounds.pew11 = Sound:new("snd/pew11.wav", 8)
  Sounds.pew12 = Sound:new("snd/pew12.wav", 8)
  Sounds.impact = Sound:new("snd/impact.mp3", 5)
  Sounds.unholster = Sound:new("snd/gun_unholster.mp3", 1)
  Sounds.launch = Sound:new("snd/launch.mp3", 15)
  Sounds.blackjack = Sound:new("snd/impact.mp3", 1) -- TODO: design a sound
  Sounds.titleLoop = Sound:new("snd/title_loop.mp3", 1)
  Sounds.titleLoop:setLooping(true)
  Sounds.roundStart = Sound:new("snd/honky-tonk-round-start.wav")
  Sounds.dealCard = Sound:new("snd/deal_card.mp3", 5)
  Sounds.scoreCounter = Sound:new("snd/score_counter.mp3", 1)
  Sounds.handSlide = Sound:new("snd/card_slide.mp3", 1)
  Sounds.handSlide:setVolume(0.2)
  Sounds.gameOver = Sound:new("snd/game_over.mp3")
end

-- Main methods
local function load()
  scene = nil
  isTransitioningScenes = false
  mostRoundsEncountered = 0
  -- Init sounds
  initSounds()
  -- Initialize game vars
  entities = {}
  -- Start at the title screen
  initTitleScreen()
end

local function update(dt)
  backgroundCycleX = (backgroundCycleX + dt) % 12.0
  backgroundCycleY = (backgroundCycleY + dt) % 16.0
  -- Update all promises
  Promise.updateActivePromises(dt)
  -- Update all entities
  local index, entity
  for index, entity in ipairs(entities) do
    if entity.isAlive and (isTransitioningScenes or entity:checkScene(scene)) then
      entity.timeAlive = entity.timeAlive + dt
      entity:update(dt)
      entity:countDownToDeath(dt)
    end
  end
  -- Remove dead entities
  entities = removeDeadEntities(entities)
  -- Sort entities for rendering
  table.sort(entities, function(a, b)
    return a.renderLayer < b.renderLayer
  end)
end

local function draw()
  -- Draw background
  local col, row
  for col = -2, math.ceil(constants.GAME_WIDTH / 40) + 2 do
    for row = -2, math.ceil(constants.GAME_HEIGHT / 20) + 2 do
      local x = 40 * col + (row % 2 == 0 and 0 or 6) + 80 * (backgroundCycleX / 12.0)
      local y = 20 * row  - 40 * (backgroundCycleY / 16.0)
      SPRITESHEET:drawCentered('BACKGROUND', x, y, 0, 0, 0, (row % 2 == 0 and 1.0 or -1.0), 1.0)
    end
  end
  -- Draw all entity shadows
  local index, entity
  for index, entity in ipairs(entities) do
    love.graphics.setColor(1, 1, 1, 1)
    entity:drawShadow()
  end
  -- Draw all entities
  for index, entity in ipairs(entities) do
    love.graphics.setColor(1, 1, 1, 1)
    entity:draw()
  end
end

local function onMousePressed(x, y)
  local isClickInsideGame = (x < constants.GAME_RIGHT and x > constants.GAME_LEFT and 
                             y > constants.GAME_TOP and y < constants.GAME_BOTTOM)
  playGunshotSound(isClickInsideGame and isGunLoaded)
  local index, entity
  for index, entity in ipairs(entities) do
    if entity.isAlive then
      entity:onMousePressed(x, y)
    end
  end
end

return {
  load = load,
  update = update,
  draw = draw,
  onMousePressed = onMousePressed
}
