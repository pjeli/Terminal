local ns = select(2, ...)

-- The game's console settings by name ("name<tab>category<tab>help" per line), for @cvar: WoW Forever
-- doesn't let addons list them, so each is checked against the game (CVars.lua). Made by tests/gen_cvars.py
-- from Ketho's BlizzardInterfaceResources (retail client). 1652 settings.
ns.CVAR_LIST = [==[
accessibilityScreenNarrationEnabled	4	Enables screen narration for accessibility
accessibilityScreenNarrationSpeechRate	4	Speed at which voice narration speaks
accessibilityScreenNarrationSpeechVolume	4	Volume at which voice narration speaks
accessibilityScreenNarrationVoice	4	Voice option used with screen narration
accountNeedsTurnStrafeDialog	4	Whether the account needs to show dialog that turn and strafe keybinds have changed
acknowledgedArrowCallouts	4	Bit field of Looking for guild player settings
ActionButtonUseKeyDown	4	Activate the action button on a keydown
ActionButtonUseKeyHeldSpell	4	Activate the press and hold cast option on a keydown
ActionCombatCameraEnable	5	enable/disable action combat camera. (default: disabled)
actionedAdventureJournalEntries	4	Which adventure journal entries flagged with ADVENTURE_JOURNAL_HIDE_AFTER_ACTION the user acted upon
activeCUFProfile	4	The last active CUF Profile.
addFriendInfoShown	4	The info for Add Friend has been shown
addonChallengeModeRestrictionsForced	4	If set, APIs guarded by challenge mode and mythic plus status will be restricted, or may return secrets.
addonChatRestrictionsForced	4	If set, APIs guarded by in lockdown will be restricted, or may return secrets.
addonCombatRestrictionsForced	4	If set, APIs guarded in combat will be restricted, or may return secrets.
addonEncounterRestrictionsForced	4	If set, APIs guarded in active encounters will be restricted, or may return secrets.
addonLoadDebugging	0	0: Disable addon load logging (Default), 1: Enable addon load logging to AddOnLoad.log.
addonMapRestrictionsForced	4	If set, APIs guarded by current map type will be restricted, or may return secrets.
addonPerformanceMsgError	4	Threshold for when a performance error is shown for a specific AddOn as a percentage of application performance.
addonPerformanceMsgOverall	4	Threshold for when an performance error is shown for all AddOns overall as a percentage of application performance.
addonPerformanceMsgWarning	4	Threshold for when a performance warning is shown for a specific AddOn as a percentage of application performance.
addonPvPMatchRestrictionsForced	4	If set, APIs guarded by PvP match state will be restricted, or may return secrets.
advancedCombatLogging	4	Whether we want advanced combat log data sent from the server
AdvFlyingDynamicFOVEnabled	4	Enables adjustment of camera field of view based on gliding speed
advFlyKeyboardMaxPitchFactor	4	Modifies the maximum pitch rate when using advFlyKeyboard.
advFlyKeyboardMaxTurnFactor	4	Modifies the maximum turn rate when using advFlyKeyboard.
advFlyKeyboardMinPitchFactor	4	Modifies the minimum pitch rate when using advFlyKeyboard.
advFlyKeyboardMinTurnFactor	4	Modifies the minimum turn rate when using advFlyKeyboard.
advFlyPitchControl	4	Modifies forward/backwards inputs to control pitch when Dragonriding.
advFlyPitchControlCameraChase	4	Modifies the speed at which camera pitch follows player pitch while dragonriding with forward/backward pitch control.
advFlyPitchControlGroundDebounce	4	If enabled, will debounce forwards/backwards inputs used to control pitch when transitioning between dragonriding and grounded.
agentUID	4	The UID provided by Battle.net to be passed to Agent
AIBrain	5	
AIController	5	
AIControllerEventLog	5	
AIEventLog	5	
allowCompareWithToggle	4	
allowDevPublicKey	6	Enable to allow the use of the Dev key instead of the one sourced from static.
AllowSoftwareRenderer	1	Allows WoW to run without a GPU. Performance will be very bad
AllowSoftwareRendererDX12	1	DX11 software render is used by default, due to issues with the DX12 software renderer
AllowSpectateMode	4	Enables spectate/commentator camera to be used.
AllowWinRT	5	Disable if WoW is crashing due to issues with the Windows GameBar
alwaysCompareItems	4	Always show item comparison tooltips
alwaysShowRuneIcons	10	Show the rune icons on equipment at all times, as opposed to only when the rune UI is open.
animFrameSkipLOD	1	animations will skip frames at distance
arachnophobiaMode	4	Swaps out spider creatures for other variants
AreaTriggerEventLog	5	
AreaTriggers	5	
assaoAdaptiveQualityLimit	1	ASSAO Adaptive Quality Limit [0.0, 1.0] (only for Quality Level 3)
assaoBlurPassCount	1	ASSAO Blur Pass Count [  0,   6] Number of edge-sensitive smart blur passes to apply. Quality 0 is an exception with only one 'dumb' blur pass used.
assaoDetailShadowStrength	1	ASSAO Detail Shadow Strength [0.0, 5.0] Used for high-res detail AO using neighboring depth pixels: adds a lot of detail but also reduces temporal stability (adds aliasing).
assaoFadeOutFrom	1	ASSAO Fade Out From [0.0,  ~ ] Distance to start start fading out the effect.
assaoFadeOutTo	1	ASSAO Fade Out To [0.0,  ~ ] Distance at which the effect is faded out.
assaoHorizonAngleThresh	1	ASSAO Horizon Angle Thresh [0.0, 0.2] Limits self-shadowing
assaoNormals	1	Use Normals for ASSAO
assaoRadius	1	ASSAO Radius [0.01,  100,000] World (view) space size of the occlusion sphere
assaoShadowClamp	1	ASSAO Shadow Clamp [0.0, 1.0]
assaoShadowMult	1	ASSAO Shadow Multiplier [0.0, 5.0] Effect strength linear multiplier
assaoShadowPower	1	ASSAO Shadow Power [0.5, 5.0] Effect strength pow modifier
assaoSharpness	1	ASSAO Sharpness [0.0, 1.0] (How much to bleed over edges; 1: not at all, 0.5: half-half; 0.0: completely ignore edges)
assaoTemporalSSAngleOffset	1	ASSAO Temporal Super Sampling Angle Offset [0.0,  PI] Used to rotate sampling kernel; If using temporal AA / supersampling, suggested to rotate by ( (frame%3)/3.0*PI ) or similar. Kernel is already symmetrical, which is why we use PI and not 2*PI.
assaoTemporalSSRadiusOffset	1	ASSAO Temporal Super Sampling Radius Offset [0.0, 2.0] Used to scale sampling kernel; If using temporal AA / supersampling, suggested to scale by ( 1.0f + (((frame%3)-1.0)/3.0)*0.1 ) or similar.
assistAttack	4	Whether to start attacking after an assist
assistedCombatHighlight	4	If enabled, a highlight will be displayed on the next spell that should be cast in combat
assistedCombatHighlightRPE	4	Will be true if Assisted Highlight was automatically enabled by RPE. Will reset when leaving RPE.
assistedCombatIconUpdateRate	4	How often (in seconds) to update the icon on the action bar, 0 for every frame, max 1 second
assistedCombatReduceHighlights	4	Reduces spell alert animations when Single-Button Assistant is on an action bar
AsyncAssistActions	5	
asyncHandlerTimeout	1	Engine option: Async read main thread timeout
asyncThreadSleep	1	Engine option: Async read thread sleep
auctionHouseDurationDropdown	4	The previously selected duration index in the auction house duration dropdown
audioLocale	4	Set the game locale for audio content
AuraDebugger	5	
AuraEventLog	5	
autoAcceptQuickJoinRequests	4	Whether or not to auto-accept players who are trying to join your party through quick join
autoClearAFK	4	Automatically clear AFK when moving or chatting
autoCompleteResortNamesOnRecency	4	Shows people you recently spoke with higher up on the AutoComplete list.
autoCompleteUseContext	4	The system will, for example, only show people in your guild when you are typing /gpromote. Names will also never be removed.
autoCompleteWhenEditingFromCenter	4	If you edit a name by inserting characters into the center, a smarter auto-complete will occur.
autoDismount	4	Automatically dismount when needed
autoDismountFlying	4	If enabled, your character will automatically dismount before casting while flying
autoFilledMultiCastSlots	4	Bitfield that saves whether multi-cast slots have been automatically filled.
autoInteract	4	Toggles auto-move to interact target
autojoinBGVoice	7	Automatically join the voice session in battleground chat
autojoinPartyVoice	7	Automatically join the voice session in party/raid chat
autoLootDefault	4	Automatically loot items when the loot window opens
autoLootRate	4	Rate in milliseconds to tick auto loot
AutoPushSpellToActionBar	4	Determines if spells are automatically pushed to the Action Bar. 0: No, 1: Yes (default).
autoQuestPopUps	4	Saves current pop-ups for quests that are automatically acquired or completed.
autoQuestProgress	4	Whether to automatically watch all quests when they are updated
autoQuestWatch	4	Whether to automatically watch all quests when you obtain them
autoSelfCast	4	Whether spells should automatically be cast on you if you don't have a valid target
autoStand	4	Automatically stand when needed
autoUnshift	4	Automatically leave shapeshift form when needed
bankAutoDepositReagents	4	Stores whether to include reagents when auto depositing items into your bank
bankConfirmTabCleanUp	4	Stores whether to show a confirmation dialog when you click the button to auto clean up your bank tabs
BeckonTriggerEventlog	5	
BehaviorTree	5	
blockChannelInvites	4	Whether to automatically block chat channel invites
blockTrades	4	Whether to automatically block trade requests
bodyQuota	1	Maximum number of componented bodies seen at once
breakUpLargeNumbers	4	Toggles using commas in large numbers
Brightness	1	Brightness adjustment. Range: [0 - 100]
buffDurations	4	Whether to show buff durations
CAADebuffSelfAlert	4	Announce when a dispellable debuff is applied to the player using a special format (0=off)
CAAEnabled	4	Enable or disable combat audio alerts
CAAInterruptCast	4	Announce when the target starts casting something interruptible
CAAInterruptCastSuccess	4	Announce when the target's cast is interrupted
CAAPartyHealthFrequency	4	Relative frequency at which party health combat audio alerts are read (-10 to 10). -10 halves the frequency and 10 doubles it
CAAPartyHealthPercent	4	Announce party member indices to indicate current health when it's below X percent. Frequency of announcements are affected by remaining health and CAAPartyHealthFrequencySpeed
CAAPartyHealthVoice	4	Voice to use for party health combat audio alerts
CAAPartyHealthVolume	4	Volume of party health combat audio alerts (0 to 100)
CAAPlayerCastFormat	4	Format string to use when reading the player's casts
CAAPlayerCastMinTime	4	The player's casts will only be read out if they have a cast time >= this
CAAPlayerCastMode	4	When the player's casts should be announced (0=off, 1=cast start, 2=cast end)
CAAPlayerCastThrottle	4	The player's casts will only be read every X seconds at most
CAAPlayerCastVoice	4	Voice to use for player cast combat audio alerts
CAAPlayerCastVolume	4	Volume of player cast combat audio alerts (0 to 100)
CAAPlayerHealthFormat	4	Format string to use when reading the player's health
CAAPlayerHealthPercent	4	Announce player health every X percent
CAAPlayerHealthThrottle	4	The player's health will only be read every X seconds at most
CAAPlayerHealthVoice	4	Voice to use for player health combat audio alerts
CAAPlayerHealthVolume	4	Volume of player health combat audio alerts (0 to 100)
CAAResource1Formats	4	Stores the format string to use (for each spec) when announcing the player's first resource
CAAResource1Percents	4	Stores the percentage band sizes to use (for each spec) when announcing the player's first resource
CAAResource1Throttle	4	Updates to the player's first resource will only be read every X seconds at most
CAAResource1Voice	4	Stores the voice to use (for each spec) when announcing the player's first resource
CAAResource1Volume	4	Stores the volume to use (for each spec) when announcing the player's first resource (0 to 100)
CAAResource2Formats	4	Stores the format string to use (for each spec) when announcing the player's second resource
CAAResource2Percents	4	Stores the percentage band sizes to use (for each spec) when announcing the player's second resource
CAAResource2Throttle	4	Updates to the player's second resource will only be read every X seconds at most
CAAResource2Voice	4	Stores the voice to use (for each spec) when announcing the player's second resource
CAAResource2Volume	4	Stores the volume to use (for each spec) when announcing the player's second resource (0 to 100)
CAASayCombatEnd	4	Announce when combat ends
CAASayCombatStart	4	Announce when combat starts
CAASayIfTargeted	4	Stores the 'say if targeted' settings for each spec
CAASayTargetName	4	Say the target's name when a new target is selected
CAASayYourDebuffs	4	Announce when a debuff is applied to the player
CAASayYourDebuffsFormat	4	Format string to use when announcing debuffs applied to the player
CAASayYourDebuffsMinDuration	4	Minimum duration of debuffs to be announced (0 means all debuffs)
CAASayYourDebuffsVoice	4	Voice to use for player debuff combat audio alerts
CAASayYourDebuffsVolume	4	Volume of player debuff combat audio alerts (0 to 100)
CAASpeed	4	Speed at which combat audio alerts are read (-10 to 10)
CAATargetCastFormat	4	Format string to use when reading the target's casts
CAATargetCastMinTime	4	The target's casts will only be read out if they have a cast time >= this
CAATargetCastMode	4	When the target's casts should be announced (0=off, 1=cast start, 2=cast end)
CAATargetCastThrottle	4	The target's casts will only be read every X seconds at most
CAATargetCastVoice	4	Voice to use for target cast combat audio alerts
CAATargetCastVolume	4	Volume of target cast combat audio alerts (0 to 100)
CAATargetDeathBehavior	4	Behavior of announcement when target dies (0=default, 1=target dead)
CAATargetHealthFormat	4	Format string to use when reading the target's health
CAATargetHealthPercent	4	Announce target health every X percent
CAATargetHealthThrottle	4	The target's health will only be read every X seconds at most
CAATargetHealthVoice	4	Voice to use for target health combat audio alerts
CAATargetHealthVolume	4	Volume of target health combat audio alerts (0 to 100)
CAAVoice	4	Primary voice to use for combat audio alerts
CAAVolume	4	Volume of combat audio alerts (0 to 100)
cacaoBilateralSimilarityDistanceSigma	1	CACAO Sigma squared value for use in bilateral upsampler giving similarity weighting for neighbouring pixels. Should be greater than 0.0.
calendarShowBattlegrounds	4	Whether Battleground holidays should appear in the calendar
calendarShowDarkmoon	4	Whether Darkmoon Faire holidays should appear in the calendar
calendarShowHolidays	4	Whether holidays should appear in the calendar
calendarShowLockouts	4	Whether raid lockouts should appear in the calendar
calendarShowResets	4	Whether raid resets should appear in the calendar
calendarShowWeeklyHolidays	4	Whether weekly holidays should appear in the calendar
cameraBobbing	4	
cameraBobbingSmoothSpeed	4	
cameraCustomViewSmoothing	4	
cameraDistanceMaxZoomFactor	4	
cameraDistanceRateMult	4	
cameraDive	4	
CameraFollowGamepadAdjustDelay	4	Delay before follow resuming after manually adjusting the camera with Gamepad input
CameraFollowGamepadAdjustEaseIn	4	Ease-in time for follow resuming after manually adjusting the camera with Gamepad input
CameraFollowOnStick	4	Enable camera to follow target as though being pushed/pulled along on a stick
CameraFollowPitchDeadZone	4	Controls pitch follow deadzone size
CameraFollowPitchSpeed	4	Controls speed of pitch following
CameraFollowPitchStrength	4	Controls strength of pitch following
CameraFollowSnapCharacterAngle	4	Angle beyond which character will snap to camera's facing when moving
CameraFollowTargetCombat	4	Camera follow the locked target only during combat.
CameraFollowYawSpeed	4	Controls speed of yaw following
cameraFov	1	Default camera field of view
cameraFoVSmoothSpeed	4	
cameraGroundSmoothSpeed	4	
cameraHeightIgnoreStandState	4	
cameraIndirectOffset	4	
cameraIndirectVisibility	4	
CameraKeepCharacterCentered	4	Motion sickness control to keep character's head at center of screen to act as motion reference point. Can override other cvar settings.
cameraPitchMoveSpeed	4	
cameraPitchSmoothMax	4	
cameraPitchSmoothMin	4	
cameraPitchSmoothSpeed	4	
cameraPivot	4	
cameraPivotDXMax	4	
cameraPivotDYMin	4	
CameraReduceUnexpectedMovement	4	Motion sickness control to reduce camera movement without player input. Can override other cvar settings.
cameraSavedDistance	4	
cameraSavedPetBattleDistance	4	
cameraSavedPitch	4	
cameraSavedVehicleDistance	4	
cameraSmooth	4	
cameraSmoothAlwaysFearDelay	4	
cameraSmoothAlwaysFearFactor	4	
cameraSmoothAlwaysIdleDelay	4	
cameraSmoothAlwaysIdleFactor	4	
cameraSmoothAlwaysMoveDelay	4	
cameraSmoothAlwaysMoveFactor	4	
cameraSmoothAlwaysStopDelay	4	
cameraSmoothAlwaysStopFactor	4	
cameraSmoothAlwaysStrafeDelay	4	
cameraSmoothAlwaysStrafeFactor	4	
cameraSmoothAlwaysTrackDelay	4	
cameraSmoothAlwaysTrackFactor	4	
cameraSmoothAlwaysTurnDelay	4	
cameraSmoothAlwaysTurnFactor	4	
cameraSmoothNeverFearDelay	4	
cameraSmoothNeverFearFactor	4	
cameraSmoothNeverIdleDelay	4	
cameraSmoothNeverIdleFactor	4	
cameraSmoothNeverMoveDelay	4	
cameraSmoothNeverMoveFactor	4	
cameraSmoothNeverStopDelay	4	
cameraSmoothNeverStopFactor	4	
cameraSmoothNeverStrafeDelay	4	
cameraSmoothNeverStrafeFactor	4	
cameraSmoothNeverTrackDelay	4	
cameraSmoothNeverTrackFactor	4	
cameraSmoothNeverTurnDelay	4	
cameraSmoothNeverTurnFactor	4	
cameraSmoothPitch	4	
cameraSmoothSmarterFearDelay	4	
cameraSmoothSmarterFearFactor	4	
cameraSmoothSmarterIdleDelay	4	
cameraSmoothSmarterIdleFactor	4	
cameraSmoothSmarterMoveDelay	4	
cameraSmoothSmarterMoveFactor	4	
cameraSmoothSmarterStopDelay	4	
cameraSmoothSmarterStopFactor	4	
cameraSmoothSmarterStrafeDelay	4	
cameraSmoothSmarterStrafeFactor	4	
cameraSmoothSmarterTrackDelay	4	
cameraSmoothSmarterTrackFactor	4	
cameraSmoothSmarterTurnDelay	4	
cameraSmoothSmarterTurnFactor	4	
cameraSmoothSmartFearDelay	4	
cameraSmoothSmartFearFactor	4	
cameraSmoothSmartIdleDelay	4	
cameraSmoothSmartIdleFactor	4	
cameraSmoothSmartMoveDelay	4	
cameraSmoothSmartMoveFactor	4	
cameraSmoothSmartStopDelay	4	
cameraSmoothSmartStopFactor	4	
cameraSmoothSmartStrafeDelay	4	
cameraSmoothSmartStrafeFactor	4	
cameraSmoothSmartTrackDelay	4	
cameraSmoothSmartTrackFactor	4	
cameraSmoothSmartTurnDelay	4	
cameraSmoothSmartTurnFactor	4	
cameraSmoothSplineFearDelay	4	
cameraSmoothSplineFearFactor	4	
cameraSmoothSplineIdleDelay	4	
cameraSmoothSplineIdleFactor	4	
cameraSmoothSplineMoveDelay	4	
cameraSmoothSplineMoveFactor	4	
cameraSmoothSplineStopDelay	4	
cameraSmoothSplineStopFactor	4	
cameraSmoothSplineStrafeDelay	4	
cameraSmoothSplineStrafeFactor	4	
cameraSmoothSplineTrackDelay	4	
cameraSmoothSplineTrackFactor	4	
cameraSmoothSplineTurnDelay	4	
cameraSmoothSplineTurnFactor	4	
cameraSmoothStyle	4	
cameraSmoothTimeMax	4	
cameraSmoothTimeMin	4	
cameraSmoothTrackingStyle	4	
cameraSmoothViewDataAlwaysDistanceDelay	4	
cameraSmoothViewDataAlwaysDistanceFactor	4	
cameraSmoothViewDataAlwaysPitchDelay	4	
cameraSmoothViewDataAlwaysPitchFactor	4	
cameraSmoothViewDataAlwaysYawDelay	4	
cameraSmoothViewDataAlwaysYawFactor	4	
cameraSmoothViewDataNeverDistanceDelay	4	
cameraSmoothViewDataNeverDistanceFactor	4	
cameraSmoothViewDataNeverPitchDelay	4	
cameraSmoothViewDataNeverPitchFactor	4	
cameraSmoothViewDataNeverYawDelay	4	
cameraSmoothViewDataNeverYawFactor	4	
cameraSmoothViewDataSmartDistanceDelay	4	
cameraSmoothViewDataSmartDistanceFactor	4	
cameraSmoothViewDataSmarterDistanceDelay	4	
cameraSmoothViewDataSmarterDistanceFactor	4	
cameraSmoothViewDataSmarterPitchDelay	4	
cameraSmoothViewDataSmarterPitchFactor	4	
cameraSmoothViewDataSmarterYawDelay	4	
cameraSmoothViewDataSmarterYawFactor	4	
cameraSmoothViewDataSmartPitchDelay	4	
cameraSmoothViewDataSmartPitchFactor	4	
cameraSmoothViewDataSmartYawDelay	4	
cameraSmoothViewDataSmartYawFactor	4	
cameraSmoothViewDataSplineDistanceDelay	4	
cameraSmoothViewDataSplineDistanceFactor	4	
cameraSmoothViewDataSplinePitchDelay	4	
cameraSmoothViewDataSplinePitchFactor	4	
cameraSmoothViewDataSplineYawDelay	4	
cameraSmoothViewDataSplineYawFactor	4	
cameraSmoothYaw	4	
cameraSubmergePitch	4	
cameraSurfacePitch	4	
cameraTargetSmoothSpeed	4	
cameraTerrainTilt	4	
cameraTerrainTiltAlwaysFallAbsorb	4	
cameraTerrainTiltAlwaysFallDelay	4	
cameraTerrainTiltAlwaysFallFactor	4	
cameraTerrainTiltAlwaysFearAbsorb	4	
cameraTerrainTiltAlwaysFearDelay	4	
cameraTerrainTiltAlwaysFearFactor	4	
cameraTerrainTiltAlwaysIdleAbsorb	4	
cameraTerrainTiltAlwaysIdleDelay	4	
cameraTerrainTiltAlwaysIdleFactor	4	
cameraTerrainTiltAlwaysJumpAbsorb	4	
cameraTerrainTiltAlwaysJumpDelay	4	
cameraTerrainTiltAlwaysJumpFactor	4	
cameraTerrainTiltAlwaysMoveAbsorb	4	
cameraTerrainTiltAlwaysMoveDelay	4	
cameraTerrainTiltAlwaysMoveFactor	4	
cameraTerrainTiltAlwaysStrafeAbsorb	4	
cameraTerrainTiltAlwaysStrafeDelay	4	
cameraTerrainTiltAlwaysStrafeFactor	4	
cameraTerrainTiltAlwaysSwimAbsorb	4	
cameraTerrainTiltAlwaysSwimDelay	4	
cameraTerrainTiltAlwaysSwimFactor	4	
cameraTerrainTiltAlwaysTaxiAbsorb	4	
cameraTerrainTiltAlwaysTaxiDelay	4	
cameraTerrainTiltAlwaysTaxiFactor	4	
cameraTerrainTiltAlwaysTrackAbsorb	4	
cameraTerrainTiltAlwaysTrackDelay	4	
cameraTerrainTiltAlwaysTrackFactor	4	
cameraTerrainTiltAlwaysTurnAbsorb	4	
cameraTerrainTiltAlwaysTurnDelay	4	
cameraTerrainTiltAlwaysTurnFactor	4	
cameraTerrainTiltNeverFallAbsorb	4	
cameraTerrainTiltNeverFallDelay	4	
cameraTerrainTiltNeverFallFactor	4	
cameraTerrainTiltNeverFearAbsorb	4	
cameraTerrainTiltNeverFearDelay	4	
cameraTerrainTiltNeverFearFactor	4	
cameraTerrainTiltNeverIdleAbsorb	4	
cameraTerrainTiltNeverIdleDelay	4	
cameraTerrainTiltNeverIdleFactor	4	
cameraTerrainTiltNeverJumpAbsorb	4	
cameraTerrainTiltNeverJumpDelay	4	
cameraTerrainTiltNeverJumpFactor	4	
cameraTerrainTiltNeverMoveAbsorb	4	
cameraTerrainTiltNeverMoveDelay	4	
cameraTerrainTiltNeverMoveFactor	4	
cameraTerrainTiltNeverStrafeAbsorb	4	
cameraTerrainTiltNeverStrafeDelay	4	
cameraTerrainTiltNeverStrafeFactor	4	
cameraTerrainTiltNeverSwimAbsorb	4	
cameraTerrainTiltNeverSwimDelay	4	
cameraTerrainTiltNeverSwimFactor	4	
cameraTerrainTiltNeverTaxiAbsorb	4	
cameraTerrainTiltNeverTaxiDelay	4	
cameraTerrainTiltNeverTaxiFactor	4	
cameraTerrainTiltNeverTrackAbsorb	4	
cameraTerrainTiltNeverTrackDelay	4	
cameraTerrainTiltNeverTrackFactor	4	
cameraTerrainTiltNeverTurnAbsorb	4	
cameraTerrainTiltNeverTurnDelay	4	
cameraTerrainTiltNeverTurnFactor	4	
cameraTerrainTiltSmarterFallAbsorb	4	
cameraTerrainTiltSmarterFallDelay	4	
cameraTerrainTiltSmarterFallFactor	4	
cameraTerrainTiltSmarterFearAbsorb	4	
cameraTerrainTiltSmarterFearDelay	4	
cameraTerrainTiltSmarterFearFactor	4	
cameraTerrainTiltSmarterIdleAbsorb	4	
cameraTerrainTiltSmarterIdleDelay	4	
cameraTerrainTiltSmarterIdleFactor	4	
cameraTerrainTiltSmarterJumpAbsorb	4	
cameraTerrainTiltSmarterJumpDelay	4	
cameraTerrainTiltSmarterJumpFactor	4	
cameraTerrainTiltSmarterMoveAbsorb	4	
cameraTerrainTiltSmarterMoveDelay	4	
cameraTerrainTiltSmarterMoveFactor	4	
cameraTerrainTiltSmarterStrafeAbsorb	4	
cameraTerrainTiltSmarterStrafeDelay	4	
cameraTerrainTiltSmarterStrafeFactor	4	
cameraTerrainTiltSmarterSwimAbsorb	4	
cameraTerrainTiltSmarterSwimDelay	4	
cameraTerrainTiltSmarterSwimFactor	4	
cameraTerrainTiltSmarterTaxiAbsorb	4	
cameraTerrainTiltSmarterTaxiDelay	4	
cameraTerrainTiltSmarterTaxiFactor	4	
cameraTerrainTiltSmarterTrackAbsorb	4	
cameraTerrainTiltSmarterTrackDelay	4	
cameraTerrainTiltSmarterTrackFactor	4	
cameraTerrainTiltSmarterTurnAbsorb	4	
cameraTerrainTiltSmarterTurnDelay	4	
cameraTerrainTiltSmarterTurnFactor	4	
cameraTerrainTiltSmartFallAbsorb	4	
cameraTerrainTiltSmartFallDelay	4	
cameraTerrainTiltSmartFallFactor	4	
cameraTerrainTiltSmartFearAbsorb	4	
cameraTerrainTiltSmartFearDelay	4	
cameraTerrainTiltSmartFearFactor	4	
cameraTerrainTiltSmartIdleAbsorb	4	
cameraTerrainTiltSmartIdleDelay	4	
cameraTerrainTiltSmartIdleFactor	4	
cameraTerrainTiltSmartJumpAbsorb	4	
cameraTerrainTiltSmartJumpDelay	4	
cameraTerrainTiltSmartJumpFactor	4	
cameraTerrainTiltSmartMoveAbsorb	4	
cameraTerrainTiltSmartMoveDelay	4	
cameraTerrainTiltSmartMoveFactor	4	
cameraTerrainTiltSmartStrafeAbsorb	4	
cameraTerrainTiltSmartStrafeDelay	4	
cameraTerrainTiltSmartStrafeFactor	4	
cameraTerrainTiltSmartSwimAbsorb	4	
cameraTerrainTiltSmartSwimDelay	4	
cameraTerrainTiltSmartSwimFactor	4	
cameraTerrainTiltSmartTaxiAbsorb	4	
cameraTerrainTiltSmartTaxiDelay	4	
cameraTerrainTiltSmartTaxiFactor	4	
cameraTerrainTiltSmartTrackAbsorb	4	
cameraTerrainTiltSmartTrackDelay	4	
cameraTerrainTiltSmartTrackFactor	4	
cameraTerrainTiltSmartTurnAbsorb	4	
cameraTerrainTiltSmartTurnDelay	4	
cameraTerrainTiltSmartTurnFactor	4	
cameraTerrainTiltSplineFallAbsorb	4	
cameraTerrainTiltSplineFallDelay	4	
cameraTerrainTiltSplineFallFactor	4	
cameraTerrainTiltSplineFearAbsorb	4	
cameraTerrainTiltSplineFearDelay	4	
cameraTerrainTiltSplineFearFactor	4	
cameraTerrainTiltSplineIdleAbsorb	4	
cameraTerrainTiltSplineIdleDelay	4	
cameraTerrainTiltSplineIdleFactor	4	
cameraTerrainTiltSplineJumpAbsorb	4	
cameraTerrainTiltSplineJumpDelay	4	
cameraTerrainTiltSplineJumpFactor	4	
cameraTerrainTiltSplineMoveAbsorb	4	
cameraTerrainTiltSplineMoveDelay	4	
cameraTerrainTiltSplineMoveFactor	4	
cameraTerrainTiltSplineStrafeAbsorb	4	
cameraTerrainTiltSplineStrafeDelay	4	
cameraTerrainTiltSplineStrafeFactor	4	
cameraTerrainTiltSplineSwimAbsorb	4	
cameraTerrainTiltSplineSwimDelay	4	
cameraTerrainTiltSplineSwimFactor	4	
cameraTerrainTiltSplineTaxiAbsorb	4	
cameraTerrainTiltSplineTaxiDelay	4	
cameraTerrainTiltSplineTaxiFactor	4	
cameraTerrainTiltSplineTrackAbsorb	4	
cameraTerrainTiltSplineTrackDelay	4	
cameraTerrainTiltSplineTrackFactor	4	
cameraTerrainTiltSplineTurnAbsorb	4	
cameraTerrainTiltSplineTurnDelay	4	
cameraTerrainTiltSplineTurnFactor	4	
cameraTerrainTiltTimeMax	4	
cameraTerrainTiltTimeMin	4	
cameraView	4	
cameraViewBlendStyle	4	
cameraWaterCollision	4	
cameraYawMoveSpeed	4	
cameraYawSmoothMax	4	
cameraYawSmoothMin	4	
cameraYawSmoothSpeed	4	
cameraZoomSpeed	4	
cameraZSmooth	4	Smooths camera vertical movement. 1 = only while moving, 2 = also while standing still
casContainerSizeLimit	5	Approximate limit in GB for the amount of game data to keep on disk at a time
characterNeedsTurnStrafeDialog	4	Whether the character needs to show dialog that turn and strafe keybinds have changed
characterSocialRestrictionSettingsApplied	4	Have the character stored settings been set to their required values for AADC restrictions.
ChatAmbienceVolume	7	Ambience Volume (0.0 to 1.0)
chatBubbles	4	Whether to show in-game chat bubbles
chatBubblesParty	4	Whether to show in-game chat bubbles for party chat
chatBubblesRaid	4	Whether to show in-game chat bubbles for raid chat
chatClassColorOverride	4	Whether or not class names are colored in chat. 0 = always color by class name (where applicable), 1 = never color by class name, 2 = respect the legacy per-channel class color settings
chatMouseScroll	4	Whether the user can use the mouse wheel to scroll through chat
ChatMusicVolume	7	Music volume (0.0 to 1.0)
ChatSoundVolume	7	Sound volume (0.0 to 1.0)
chatStyle	4	The style of Edit Boxes for the ChatFrame. Valid values: "classic", "im"
checkAddonVersion	4	Check interface addon version number
ChromaEffectsEnable	5	Enable chroma effects on supported peripherals
ChromaEffectsFactionColor	5	Enable setting chroma base layer color to match current faction
ClientCastDebug	0	debug client cast allocation
ClientCastLimitDebug	0	Limits the maximum allowed initiated casts in progress.
ClientMessageEventLog	5	
ClientSettings_AFTERMATH_BY_API_MASK	5	
ClientSettings_AFTERMATH_BY_GPU_CATEGORY	5	
ClientSettings_ASYNC_COMPUTE_BY_API_MASK	5	
ClientSettings_ASYNC_COMPUTE_BY_GPU_CATEGORY	5	
ClientSettings_ClusteredShading	5	
ClientSettings_CMAA2	5	
ClientSettings_CMD_LIST_MT_BY_API_MASK	5	
ClientSettings_CMD_LIST_MT_BY_GPU_CATEGORY	5	
ClientSettings_COPY_QUEUE_BY_API_MASK	5	
ClientSettings_COPY_QUEUE_BY_GPU_CATEGORY	5	
ClientSettings_CTexAsyncCreate	5	
ClientSettings_FSR	5	
ClientSettings_HIGH_MEM_FEATURES_BY_API_MASK	5	
ClientSettings_HIGH_MEM_FEATURES_BY_GPU_CATEGORY	5	
ClientSettings_LowLatency	5	
ClientSettings_LowVramActions	5	
ClientSettings_MemoryAllocationTraces	5	
ClientSettings_MSAA	5	
ClientSettings_NeedsGxRestart	5	
ClientSettings_OPT_FEATURES_BY_API_MASK	5	
ClientSettings_OPT_FEATURES_BY_GPU_CATEGORY	5	
ClientSettings_RAY_TRACING_BY_API_MASK	5	
ClientSettings_RAY_TRACING_BY_GPU_CATEGORY	5	
ClientSettings_RTShadows	5	
ClientSettings_SHADER_MT_BY_API_MASK	5	
ClientSettings_SHADER_MT_BY_GPU_CATEGORY	5	
ClientSettings_SM6_BY_API_MASK	5	
ClientSettings_SM6_BY_GPU_CATEGORY	5	
ClientSettings_SpellClutter	5	
ClientSettings_VolumeFog	5	
ClientSettings_WORK_OPTIMS_BY_API_MASK	5	
ClientSettings_WORK_OPTIMS_BY_GPU_CATEGORY	5	
ClipCursor	1	Lock the cursor to the game window
cloakFixEnabled	5	
closedExtraAbiltyTutorials	4	Bitfield for which extra ability tutorials have been acknowledged by the user
closedInfoFrames	4	Bitfield for which help frames have been acknowledged by the user
closedInfoFramesAccountWide	4	Bitfield for which help frames have been acknowledged by the user (account-wide)
closedRemixArtifactTutorialFrames	4	Tutorial bitfield for which Remix Artifacts have been shown so far
clubFinderCacheExpiry	4	Value in (MS) for time to expire the cache.
clubFinderCachePendingExpiry	4	Value in (MS) for time to expire the cache.
clubFinderPlayerLanguageSettings	4	Bit field of Looking for club/guild player language settings
clubFinderPlayerSettings	4	Bit field of Looking for guild player settings
clusteredShading	1	Allow forward transparent lighting
CMAA2ExtraSharpness	1	Set to 1 to preserve even more text and shape clarity at the expense of less AA
CMAA2HalfFloat	1	0: 32-bit Float. 1: 16-bit Float.
CMAA2Quality	1	CMAA2 Quality Level. 0 - LOW, 1 - MEDIUM, 2 - HIGH, 3 - ULTRA
collapsedCurrencyCategoryDefaults	4	Stores the IDs of currency categories that should be collapsed by default in the Token UI
collapsedReputationHeaderDefaults	4	Stores the IDs of headers that should be collapsed by default in the Reputation Panel
collapseExpandBuffs	4	Enables a button to collapse and hide long duration buffs.
Collision	5	
colorblindMode	4	Enables colorblind accessibility features in the game
colorblindSimulator	1	Type of color blindness
colorblindWeaknessFactor	1	Amount of sensitivity. e.g. Protanope (red-weakness) 0.0 = not colorblind, 1.0 = full weakness(Protanopia), 0.5 = mid weakness(Protanomaly)
colorChatNamesByClass	4	If enabled, the name of a player speaking in chat will be colored according to his class.
combatLogRetentionTime	4	The maximum duration in seconds to retain combat log entries
combatLogUniqueFilename	4	Write combat log file with a timestamped name per client launch
combatWarningsEnabled	4	If set, enables combat warning UI functionality such as the boss timeline or warnings displays
combinedBags	4	Use combined bag frame for all bags
comboPointLocation	4	Location of combo points in UI. 1=target, 2=self
commentatorLossOfControlIconUnitFrame	4	0: Off, 1: On.
commentatorLossOfControlTextNameplate	4	0: Off, 1: On.
commentatorLossOfControlTextUnitFrame	4	0: Off, 1: On.
communitiesShowOffline	4	Show offline community members in the communities frame roster
componentCompress	1	Character component texture compression
componentEmissive	1	Character component unlit/emissive
componentSpecular	1	Character component specular highlights
componentTexCacheSize	1	Character component texture cache size (in MB)
componentTexLoadLimit	1	Character component texture loading limit per frame
componentTextureLevel	1	Level of detail for character component textures. 0 means full detail.
componentThread	1	Multi thread character component processing
ConsoleKey	2	Set key that opens the console
consoleShowDebugMessages	0	Controls if log messages with Debug priority are displayed to console.
consoleShowSpamMessages	0	Controls if log messages with Spam priority are displayed to console.
contentTrackingFilter	4	If enabled, tracked items will display on the world map.
ContentTuning	5	
Contrast	1	Contrast adjustment. Range: [0 - 100]
cooldownViewerEnabled	4	If true, show the cooldown viewer UI.
cooldownViewerShowUnlearned	4	In the cooldown viewer settings UI, determines whether or not to show unlearned cooldowns
countdownForCooldowns	4	Whether to use number countdown instead of radial swipe for action button cooldowns or not.
covenantMissionTutorial	4	Stores information about which covenant mission/adventures tutorials the player has seen
craftingOrdersOnlyPreferredArmorCollectable	4	Determines if crafting orders can treat armor that doesn't match the players best/preferred armor type as collectable
currencyCategoriesCollapsed	4	Internal CVar for tracking collapsed currency categories.
currentGameMode	4	The record ID of the current realm's GameMode. -1 means none, which may happen before connecting to a realm. 0 means the executable's standard game mode.
CursorCenteredYPos	5	0-1 vertical position of centered cursor/targeting (0 at bottom)
CursorFreelookCentering	5	Center the cursor when using Mouse freelook
CursorFreelookStartDelta	5	Fraction of the screen the cursor must move to start freelook after mouse button goes down
cursorSizePreferred	1	Size of cursor: -1=determine based on system/monitor dpi, 0=32x32, 1=48x48, 2=64x64, 3=96x96, 4=128x128
CursorStickyCentering	5	Make the centered position stick after freelook; Don't restore previous cursor position
CustomDesignEventLog	5	
CustomWindowEventLog	5	
daltonize	1	Attempt to correct for color blindness (set colorblindSimulator to type of colorblindness)
DamageCalculator	5	
damageMeterEnabled	4	If true, show the damage meter UI.
damageMeterResetOnNewInstance	4	If true, reset the damage meter any time the player enters a new instance.
dangerousShipyardMissionWarningAlreadyShown	4	Boolean indicating whether the shipyard's dangerous mission warning has been shown
DebugTorsoTwist	0	Debug visualization for Torso Twist: 1 = Player, 2 = Target, 3 = All
DeprecatedWarningThrottle	5	Time since last warning. A value of "1" will disable this message
DepthBasedOpacity	1	Enable/Disable Soft Edge Effect
deselectOnClick	4	Clear the target when clicking on terrain
developerLog	0	Enables Developer Log - 0: Disabled (default), 1: Enabled.
developerLogFilterDebug	0	Show Debug messages in Developer Log - 0: Disabled (default), 1: Enabled.
developerLogFilterError	0	Show Error messages in Developer Log - 0: Disabled, 1: Enabled (default).
developerLogFilterFatal	0	Show Fatal messages in Developer Log - 0: Disabled, 1: Enabled (default).
developerLogFilterNormal	0	Show Normal messages in Developer Log - 0: Disabled, 1: Enabled (default).
developerLogFilterSpam	0	Show Spam messages in Developer Log - 0: Disabled (default), 1: Enabled.
developerLogFilterWarning	0	Show Warning messages in Developer Log - 0: Disabled, 1: Enabled (default).
developerLogWriteToFile	0	Enables Developer Log Write to File - 0: Disabled, 1: Enabled (default).
digSites	4	If enabled, the archaeological dig site system will be used.
DisableAdvancedFlyingFullScreenEffects	4	Disable the advanced flying full screen effects
DisableAdvancedFlyingVelocityVFX	4	Disable the advanced flying velocity VFX
disableAELooting	4	Disable AoE Looting
disableAutoRealmSelect	5	Disable automatically selecting a realm on login
disableServerNagle	6	Disable server-side nagle algorithm
disableSuggestedLevelActivityFilter	4	Whether to disable filtering the activity list by the user's level.
disableUILoadErrorDialog	0	Disables showing an os dialog on critical UI error startup
disableUserAddonsByDefault	4	Setting this will result in newly installed addons to be disabled by default
discordClientEnabled	0	Enable the discord client integration
discordDisplayName	4	The name to show for text from you in-game from Discord
displaySpellActivationOverlays	4	Whether to display Spell Activation Overlays (a.k.a. Spell Alerts)
displayWorldPVPObjectives	4	Whether to show world PvP objectives
dnMTUpdate	1	Update Daynight in parralel.
doNotFlashLowHealthWarning	4	Do not flash your screen red when you are low on health.
doNotShowTWFraudWarning	4	If set, the TW Fraud Warning dialog will not show on startup
dontShowEquipmentSetsOnItems	4	Don't show which equipment sets an item is associated with
doodadLodScale	1	Doodad level of detail scale
dragonRidingRacesFilter	4	If enabled, dragonriding races will display on the world map at zone level.
dragonRidingRacesFilterWQ	4	If enabled, dragonriding races WQ will display on the world map at zone level.
DriveDynamicFOVEnabled	4	Enables adjustment of camera field of view based on driving speed
DriverVersionCheck	1	Set 0 to disable driver version based workarounds
DriveSwapReverseTurnDirection	4	Boolean indicating if we should swap turn directions when driving in reverse. By default, Drive uses the opposite turn direction when moving backwards.
dynamicLod	1	Dynamic level of detail adjustment
DynamicRenderScale	1	Lowers render scale if GPU bound to hit Target FPS. Note this feature is in BETA. Known issues: May cause hitching. May behave poorly with vsync on.
DynamicRenderScaleMin	1	Lowest render scale DynamicRenderScale can use
EJDungeonDifficulty	4	Stores the last dungeon difficulty viewed in the encounter journal
EJLootClass	4	Stores the last class that loot was filtered by in the encounter journal
EJLootSpec	4	Stores the last spec that loot was filtered by in the encounter journal
EJRaidDifficulty	4	Stores the last raid difficulty viewed in the encounter journal
EJSelectedTier	4	Stores the last manually selected journal tier in the encounter journal
EmitterCombatRange	4	Range to stop shoulder/weapon emissions during combat
emphasizeMySpellEffects	4	Whether other player's spell impacts are toned down or not.
EmpowerMinHoldStagePercent	4	Sets a percentage of the first empower stage [0.0,1.0]. Before this point, the spell will be auto-held. After it, releases will be accepted.
empowerTapControls	4	By default, Empower spells use a press-hold-release control scheme. Set this CVar to use a tap-tap scheme instead.
EmpowerTapControlsReleaseThreshold	4	Sets the time in milliseconds after which release/re-hold requests will be registered for press-and-tap empowers. Begins when the cast is sent from the client.
enableAssetTracking	4	Whether to track which assets are least recently used
enableBGDL	6	Background Download (on async net thread) Enabled
EnableBlinkApplicationIcon	4	Allows the client to blink the application icon in the taskbar in Windows, or bounce the application icon in the dock on macOS
enableConnectToPhotoSharing	4	Enables the photo sharing connection feature.
enableFloatingCombatText	4	Whether to show floating combat text for the player
enableMouseoverCast	4	Whether mouseover casting is enabled (optionally with a modifier key).
enableMouseSpeed	4	Enables setting a custom mouse sensitivity to override the setting from the operating system.
enableMovePad	4	Enables the MovePad accessibility feature in the game
enableMultiActionBars	4	Bits for which additional action bars to show
enablePetBattleFloatingCombatText_v2	4	Whether to show floating combat text for pet battles
enablePings	4	Enables ping system.
enablePVPNotifyAFK	4	The ability to shutdown the AFK notification system
enableQuestCacheLogging	4	Enable logging for requests for the QuestCache
enableRuneSpentAnim	5	Adjust the time the rune fades after it flashes when you spend it
enableSourceLocationLookup	0	Allows addon file name lookup for debugging help
enableWowMouse	5	Enable Steelseries World of Warcraft Mouse
encounterTimelineEnabled	4	If true, enable the encounter timeline UI.
encounterTimelineHideForOtherRoles	4	If true, hide encounter timeline events that are relevant for roles other than the player's own group role assignment. Events with no assigned role will always be shown.
encounterTimelineHideLongCountdowns	4	If true, hide all long countdowns from the timeline.
encounterTimelineHideQueuedCountdowns	4	If true, hide all queued countdowns from the timeline.
encounterTimelineHighlightDuration	4	Milliseconds at which events will be signaled to trigger a highlight glow animation.
encounterTimelineIconographyEnabled	4	If true, enable the display of spell support iconography such as role and effect type indicators.
encounterTimelineShowSequenceCount	4	If true, display the spell sequence count in encounter timeline spell names
encounterWarningsDefaultMessageDuration	4	Default duration (in milliseconds) applied to encounter warning text messages
encounterWarningsEnabled	4	If true, enable the display of encounter warning messages
encounterWarningsHideIfNotTargetingPlayer	4	If true, hide messages that aren't actively targeting the player. Messages that have no explicit target will always be shown
encounterWarningsLevel	4	Minimum level of encounter warning severities to be shown
endeavorInitiativesLastPointsMap	4	Last seen number of endeavor points in the progress bar per initiative ID
engineSurvey	4	Engine Survey Index
engineSurveyPatch	4	Engine Survey Patch
entityLodDist	1	Entity level of detail distance
entityLodOffset	1	Entity level of detail offset
entityShadowFadeScale	1	Entity shadow fade scale
equipmentManager	4	Enables the equipment management UI
ErrorFilter	0	
ErrorLevelMax	0	
ErrorLevelMin	0	
Errors	0	
eventReminders	4	Internal cvar for saving event reminders
eventSchedulerLastUpdate	4	Stores the last time the event scheduler UI was update, for anim purposes
excludedCensorSources	4	Inappropriate message source exemptions. 0 = Exempt nobody, 1 = Exempt Friends, 3 = Exempt Friends and Guildmates, 255 = Exempt All
ExclusiveWindowMode	5	Accessibility option for preventing the game window from losing focus
expandBagBar	4	Expand the main menu bar that shows the bags so you can see all equipped bags instead of just the backpack and reagent bag
expandUpgradePanel	4	Controls whether the upgrade panel is expanded or collapsed.
expandWarbandCharacterList	4	Stores if the warband character list is expanded or collapsed.
externalDefensivesEnabled	4	If true, show the external defensives buff tracker UI.
farclip	1	Far clip plane distance
ffxAntiAliasingMode	1	Anti Aliasing Mode
ffxDeath	1	full screen death desat effect
ffxGlow	1	full screen glow effect
ffxLingeringVenari	1	full screen Lingering Cloak of Ven'ari effect
ffxNether	1	full screen nether effect
ffxVenari	1	full screen Cloak of Ven'ari effect
findYourselfAnywhere	4	Always Highlight your character
findYourselfAnywhereOnlyInCombat	4	Highlight your character only when in combat
findYourselfInBG	4	Always Highlight your character in Battlegrounds
findYourselfInBGOnlyInCombat	4	Highlight your character in Battlegrounds only when in combat
findYourselfInRaid	4	Always Highlight your character in Raids
findYourselfInRaidOnlyInCombat	4	Highlight your character in Raids only when in combat
findYourselfMode	4	Highlight your character. 0 = circle, 1 = circle & outline, 2 = outline
findYourselfModeCircle	4	Highlight your character with a circle.
findYourselfModeIcon	4	Highlight your character with an icon.
findYourselfModeOutline	4	Highlight your character with an outline.
flaggedTutorials	4	Internal cvar for saving completed tutorials in order
flashErrorMessageRepeats	4	Flashes the center screen red error text if the same message is fired.
flightAngleLookAhead	4	Enables more dynamic attitude adjustments while flying
floatingCombatTextAuraFade_v2	4	
floatingCombatTextAuras_v2	4	
floatingCombatTextCombatDamage_v2	4	Display damage numbers over hostile creatures when damaged
floatingCombatTextCombatDamageAllAutos_v2	4	Show all auto-attack numbers, rather than hiding non-event numbers
floatingCombatTextCombatDamageDirectionalOffset_v2	4	Amount to offset directional damage numbers when they start
floatingCombatTextCombatDamageDirectionalScale_v2	4	Directional damage numbers movement scale (0 = no directional numbers)
floatingCombatTextCombatHealing_v2	4	Display amount of healing you did to the target
floatingCombatTextCombatHealingAbsorbSelf_v2	4	Display amount of shield added to yourself.
floatingCombatTextCombatHealingAbsorbTarget_v2	4	Display amount of shield added to the target.
floatingCombatTextCombatLogPeriodicSpells_v2	4	Display damage caused by periodic effects
floatingCombatTextCombatState_v2	4	
floatingCombatTextComboPoints_v2	4	
floatingCombatTextDamageReduction_v2	4	
floatingCombatTextDodgeParryMiss_v2	4	
floatingCombatTextEnergyGains_v2	4	
floatingCombatTextFloatMode_v2	4	The combat text float mode for the player
floatingCombatTextFriendlyHealers_v2	4	
floatingCombatTextHonorGains_v2	4	
floatingCombatTextLowManaHealth_v2	4	
floatingCombatTextPeriodicEnergyGains_v2	4	
floatingCombatTextPetMeleeDamage_v2	4	Display pet melee damage in the world
floatingCombatTextPetSpellDamage_v2	4	Display pet spell damage in the world
floatingCombatTextReactives_v2	4	
floatingCombatTextRepChanges_v2	4	
FootstepSounds	7	play footstep sounds
forceClusteredShading	1	Force clustered forward lighting for all transparent objects
forceEnglishNames	5	
ForceGenerateSlug	0	Generate .slug files for all loaded fonts before they are actually used rather than deferred load.
forceLODCheck	1	If enabled, we will skip checking DBC for LOD count and every m2 will scan the folder for skin profiles
ForceResolutionDefaultToMaxSize	1	Force default resolution to the maximum supported size rather than the auto-detected size
FrameBufferCacheForceNoHeaps	1	Disable use of texture heaps and force the fallback path
frameScriptFunctionInheritanceWarningMode	0	Displays Lua errors about script handlers that are using inheritance improperly (might add more modes in the future, 0 is off, 1 is on)
friendInvitesCollapsed	4	Whether friend invites are hidden in the friends list
fstack_enabled	0	0: Hide Framestack Tooltip (Default), 1: Show Framestack Tooltip.
fstack_preferParentKeys	0	0: Prefer Global Names, 1: Prefer ParentKeys (Default).
fstack_showanchors	0	0: Hide Anchors, 1: Show Anchors (Default).
fstack_showhidden	0	0: Hide Hidden (Default), 1: Show Hidden.
fstack_showhighlight	0	0: Hide Highlight, 1: Show Highlight (Default).
fstack_showRaisedFrameLevels	0	0: Show normal frame levels (default), 1: Show raised frame levels instead
fstack_showregions	0	0: Hide Regions, 1: Show Regions (Default).
GameDataVisualizer	5	
GamePadAnalogMovement	5	Enable analog movement in any direction, rather than just the 8 cardinal directions
GamePadCameraLookMaxPitch	5	Max pitch 'Look' stick can adjust camera angle
GamePadCameraLookMaxYaw	5	Max yaw 'Look' stick can adjust camera angle
GamePadCameraPitchSpeed	5	Pitch speed of GamePad camera moving up/down
GamePadCameraYawSpeed	5	Yaw speed of GamePad camera turning left/right
GamePadCursorAutoDisableJump	5	GamePad cursor control will auto-disable when you jump
GamePadCursorAutoDisableSticks	5	GamePad cursor control will auto-disable on stick input (0=none, 1=movement, 2=movement+cursor)
GamePadCursorAutoEnable	5	Auto enable GamePad cursor control when opening UIs that may need it
GamePadCursorCenteredEmulation	5	When cursor is centered for GamePad movement, also emulate mouse clicks
GamePadCursorCentering	5	When using GamePad, center the cursor
GamePadCursorForTargeting	5	Enable GamePad controlled cursor for spell targeting (1=enable, 2=start-at-target)
GamePadCursorLeftClick	5	GamePad button that should emulate mouse Left Click while controlling the mouse cursor
GamePadCursorOnLogin	5	Enable GamePad cursor control on login and character screens
GamePadCursorPushCamera	5	Rate for GamePad controlled cursor to push/turn camera when at edge of window
GamePadCursorRightClick	5	GamePad button that should emulate mouse Right Click while controlling the mouse cursor
GamePadCursorSpeedAccel	5	Acceleration of GamePad cursor per second as it continues to move
GamePadCursorSpeedMax	5	Top speed of GamePad cursor movement
GamePadCursorSpeedStart	5	Speed of GamePad cursor when it starts moving
GamePadEmulateAlt	5	GamePad button that should emulate the Alt key
GamePadEmulateCtrl	5	GamePad button that should emulate the Ctrl key
GamePadEmulateShift	5	GamePad button that should emulate the Shift key
GamePadEmulateTapWindowMs	5	GamePad buttons emulating Ctrl/Alt/Shift will be 'tapped' if released withing this time in MS
GamePadEnable	5	Whether GamePad input should be enabled
GamePadFaceMovementMaxAngle	5	Max movement to camera angle to face movement direction instead of camera direction. 0 = always, 180 = never (115 allows using strafe with quick turn around)
GamePadFaceMovementMaxAngleCombat	5	Max movement to camera angle to face movement direction instead of camera direction, in combat. 0 = always, 180 = never (115 allows using strafe with quick turn around)
GamePadFactionColor	5	Enable setting GamePad's led color to match current faction
GamePadOverlapMouseMs	5	Duration after gamepad+mouse input to switch to just one or the other.
GamePadRunThreshold	5	0-1 Amount of stick movement before character transitions from walk to run
GamePadSingleActiveID	5	ID of single GamePad device to use. 0 = Use all devices' combined input
GamePadStickAxisButtons	5	Enables virtual buttons for the GamePad stick cardinal directions
GamePadTankTurnSpeed	5	If non-zero, character turns like a tank from GamePad movement
GamePadTouchCursorEnable	5	Enable cursor control with GamePad's touch pad
GamePadTurnWithCamera	5	Turn character to match when camera facing is changed (1=in-combat, 2=always)
GamePadVibrationStrength	5	GamePad vibration effect strength
GameplayContext	5	
gameTip	5	
Gamma	1	Gamma correction. Range: [0.3 - 2.8]
garrisonCompleteTalent	4	
garrisonCompleteTalentType	4	
graphicsComputeEffects	1	UI value of the graphics setting
graphicsDepthEffects	1	UI value of the graphics setting
graphicsEnvironmentDetail	1	UI value of the graphics setting
graphicsGroundClutter	1	UI value of the graphics setting
graphicsLiquidDetail	1	UI value of the graphics setting
graphicsOutlineMode	1	UI value of the graphics setting
graphicsParticleDensity	1	UI value of the graphics setting
graphicsProjectedTextures	1	UI value of the graphics setting
graphicsQuality	5	save for Graphics Quality Selection
graphicsShadowQuality	1	UI value of the graphics setting
graphicsSpellDensity	1	UI value of the graphics setting
graphicsSSAO	1	UI value of the graphics setting
graphicsTextureResolution	1	UI value of the graphics setting
graphicsViewDistance	1	UI value of the graphics setting
groundEffectDensity	1	Ground effect density
groundEffectDist	1	Ground effect dist
groundEffectFade	1	Ground effect fade
guildMemberNotify	4	Whether to notify when guild members come online or go offline
guildNewsFilter	4	Stores the guild news filters
guildRewardsCategory	4	Show category of guild rewards
guildRewardsUsable	4	Show usable guild rewards only
guildShowOffline	4	Show offline guild members in the guild UI
GxAdapter	1	Set which GPU to use. See GxListGPUs for valid names (empty string to let client choose)
GxAFRDevicesCount	1	Force to set number of AFR devices
GxAllowCachelessShaderMode	1	CPU memory saving mode, if supported by backend. When enabled, shaders are fetched from disk as needed instead of being kept resident. This mode may slightly increase the time objects take to appear the first time they are encountered. Computers without solid state drives may want to disable this feature
GxApi	1	graphics api
GxCompatAllowSM6	5	When disabled, DX12 will use Shader Model 5 shaders instead of Shader Model 6
GxCompatAsyncComputeQueue	5	Allows some compute work to run on a different GPU work queue
GxCompatAsyncShaderCompilation	5	Allows async resource shader loading. Disabling this may cause hitching
GxCompatCommandListMultiThreading	5	Allow multi-threaded rendering. Disabling this will significantly reduce framerate
GxCompatCopyQueue	5	Allows GPU upload work to run on a different GPU work queue
GxCompatOptionalGpuFeatures	5	When disabled, makes the engine act as if the GPU only supports the minimum supported feature set
GxCompatWorkSubmitOptimizations	5	Allows GPU work submission on a secondary thread while the rest of the CPU threads continue on to the next frame
GxFullscreenResolution	5	resolution
GxMaxFrameLatency	1	maximum number of frames ahead of GPU the CPU can be
GxMaximize	5	toggle fullscreen/window
GxMonitor	1	Monitor index. 0 means use the primary monitor
gxMTAlphaM2	1	Render transparent M2 pass in parallel.
gxMTAlphaPass	1	Render Alpha Pass in parallel.
gxMTBeginDraw	1	Do BeginDraw multithreaded.
gxMTDecals	1	Sort and Render decal passes in parallel. Note enabling this currently will cause visual artifacts in some cases.
gxMTDisable	1	Disable all render multithreading
gxMTLightShafts	1	Render light-shaft passes in parallel
gxMTMisc	1	Render miscelleous passes in parallel
gxMTOpaqueM2	1	Render opaque model pass in parallel.
gxMTOpaqueM2NoReflect	1	Render opaque model no reflection pass in parallel.
gxMTOpaqueWMO	1	Render opaque WMO in parallel.
gxMTOutlines	1	Render outline passes in parallel
gxMTPrepass	1	Render prepass in parallel.
gxMTRefraction	1	Render refraction pass in parallel
gxMTShadow	1	Render shadow bands in parallel.
gxMTTerrain	1	Render terrain in parallel.
gxMTTriggerOnBeginDrawComplete	1	Use Begin Draw Complete Trigger Mechanism
gxMTVolFog	1	Render volumetric fog in parallel
GxNewResolution	1	resolution to be set
GxPrismEnabled	1	0: Prism backends Disabled. 1: Default Prism backends Enabled. 2: Experimental Prism backends Enabled.
GxSlowShaderWarnThreshold	1	Max time (in milliseconds) the shader compile can take before warning via a popup message
GxWindowedResolution	5	windowed resolution
hardcoreDeathAlertType	4	
hardcoreDeathChatType	4	
hardTrackedQuests	4	Internal cvar for saving user manually tracked quests in order
hardTrackedWorldQuests	4	Internal cvar for saving user manually tracked world quests
HardwareCursor	1	If disabled, draws a software cursor (can be used to have cursor appear in screenshots)
HealHandler	5	
heirloomCollectedFilters	4	Bitfield for which collected filters are applied in the heirloom journal
heirloomSourceFilters	4	Bitfield for which source filters are applied in the heirloom journal
hideFastLoginLoadingScreen	6	Hide the loading screen when fast logging in
hideRewardedEvents	4	Stores whether to hide events whose rewards have been claimed
highestUnlockedTieredEntranceTier	4	Serialized mapping using a PDE ID. Stores the highest unlocked difficulty tier. Used to notify the player when they have higher difficulty tiers available.
horizonClip	1	Horizon end distance
horizonStart	1	Horizon start distance
HotfixEventLog	5	
hotReloadModels	1	Allow an active model to be reloaded when a new version is detected in the bin folder.  If this is disabled, the model data will only be refreshed after all game objects using the model are deleted
houseExterior_Hide_Decor	4	Whether or not to hide all decor on the plot while in Exterior Customization
housingDecorFreePlaceEnabled	4	Whether or not free placement in decor edit modes is enabled
housingDecorGridSnapEnabled	4	Whether or not snap-to-grid in decor edit modes is enabled
housingDecorGridVisible	4	Whether or not the grid in decor edit modes is visible
housingDecorLightRadiusIndicatorsEnabled	4	Whether or not the light radius indicators in decor edit modes are visible
housingExpertGizmos_Scale_FrameOffset	10	Y Offset of scale frame from target
housingExpertGizmos_Scale_Snap	10	Amount scale should snap (0.1 being 10%, 1 being 100%, etc)
housingExpertGizmos_SnapOnHold	10	true: Holding shift turns expert control snapping on, false: Holding shift turns snapping off
housingLayout_Camera_DefaultDistance	10	Default height of the layout edit mode camera above the floor
housingLayout_Camera_DragFriction	10	How quickly the camera loses drag momentum
housingLayout_Camera_DragMomentum	10	How much momentum does the camera have after the user stops dragging
housingLayout_Camera_MaxDistance	10	Maximum height of the layout edit mode camera above the floor
housingLayout_Camera_MaxDistanceIncr	10	How much zoom in/out of the layout edit mode camera affects distance from the floor
housingLayout_Camera_MinDistance	10	Minimum height of the layout edit mode camera above the floor
housingLayout_Camera_Smoothness	10	Smoothness factor of layout camera movement
housingLayout_Camera_Speed	10	Units/second that the layout edit mode camera moves
housingOtherDecorLightRadiusIndicatorType	4	Choose how light radius indicator is shown for non-selected decor
housingSelectedDecorLightRadiusIndicatorType	4	Choose how light radius indicator is shown for selected decor
housingStoragePanelCollapsed	4	Whether the housing storage panel is collapsed
housingStoragePanelHeight	4	The saved height of the housing storage panel
housingStoragePanelWidth	4	The saved width of the housing storage panel
housingTutorialsEnabled	4	Housing tutorials enabled or disabled
hwDetect	1	do hardware detection
imageSharingPublishCooldown	4	Amount of time between allowed photo publish attempts (in milliseconds).
ImpactModelCollisionMelee	4	Enable model collision checks for melee impact effects
ImpactModelCollisionMissile	4	Enable model collision checks for missile impact effects
ImpactModelCollisionRanged	4	Enable model collision checks for ranged attack impact effects
incompleteQuestPriorityThresholdDelta	0	
initialRealmListTimeout	5	How long to wait for the initial realm list before failing login (in seconds)
interactKeyWarningTutorial	4	Has the player seen the interact key warning tutorial since they have logged in
interactOnLeftClick	4	Test CVar for interacting with NPC's on left click
interactQuestItems	4	Enable Quest Item use as an interaction
InvalidateDeactivatedHandles	0	Turn on to treat WowCS Handles as invalid if referring to a deactivated entity
KioskCanSessionExpire	8	Determines if a Kiosk session can expire. 0: No, 1: Yes (default).
KioskCharacterTemplateSet	8	Character template set ID to select at character creation. Defaults to 0.
KioskLobbyKickSeconds	8	Seconds until an expired session kicks the player back to the lobby. Defaults to 30 seconds.
lastAddonVersion	4	Addon interface version number from previous build
lastCharacterIndex	4	Last character selected
lastGarrisonMissionTutorial	4	Stores the last garrison mission tutorial the player has accepted
lastLaunchedExternalEventURL	4	
lastLockedDelvesCompanionAbilities	4	Stores the nodeIDs of the locked delve companion abilities, to highlight them when unlocked.
lastLockedTieredEntranceCompanionAbilities	4	Serialized mapping using a PDE ID. Stores the nodeIDs of the locked delve companion abilities, to highlight them when unlocked.
lastRenownForCovenant1	4	Stores the Kyrian renown when Renown UI is closed
lastRenownForCovenant2	4	Stores the Venthyr renown when Renown UI is closed
lastRenownForCovenant3	4	Stores the NightFae renown when Renown UI is closed
lastRenownForCovenant4	4	Stores the Necrolord renown when Renown UI is closed
lastRenownForDelvesSeason	4	Stores the Delves Season faction renown when Renown UI is closed
lastSelectedClubId	4	The last club that was selected by the user. We default to this club when the player opens the communities frame if the player isn't in a guild.
lastSelectedTieredEntranceTier	4	Serialized mapping using a PDE ID. Stores the last selected difficulty tier. If 0, the player will be forced to select a tier.
lastTalkedToGM	4	Stores the last GM someone was talking to in case they reload the UI while the GM chat window is open.
lastTransmogCustomSetIDNoSpec	4	SetID of the last applied transmog custom set
lastTransmogCustomSetIDSpec1	4	SetID of the last applied transmog custom set for the 1st spec
lastTransmogCustomSetIDSpec2	4	SetID of the last applied transmog custom set for the 2nd spec
lastTransmogCustomSetIDSpec3	4	SetID of the last applied transmog custom set for the 3rd spec
lastTransmogCustomSetIDSpec4	4	SetID of the last applied transmog custom set for the 4th spec
lastTransmogOutfitIDNoSpec	4	SetID of the last applied transmog outfit
latestSplashScreen	4	The ID of the latest splash screen from the UISPLASHSCREEN table.
latestTransmogSetSource	4	itemModifiedAppearanceID of the latest collected source belonging to a set
launchAgent	4	Set this to have the client start up Agent
lfdCollapsedHeaders	4	Stores which LFD headers are collapsed.
lfdSelectedDungeons	4	Stores which LFD dungeons are selected.
lfgListAdvancedFilterMinRating	4	Minimum mythic plus rating of the leader of the group to find
lfgListAdvancedFilterRemovedActivities	4	List of activity IDs to filter against
lfgListAdvancedFilters	4	Advanced LFG filters for dungeons that are booleans
lfgListAdvancedFiltersVersion	4	Version for lfgListAdvancedFilters
lfgListSearchLanguages	4	A simple bitfield for what languages we want to search in.
lfgSelectedRoles	4	Stores what roles the player is willing to take on.
loadDeprecationFallbacks	4	When enabled, Deprecation_* addons are loaded to provide fallbacks for deprecated script APIs.
locale	5	Set the game locale
locateViewerMaxJobs	1	Maximum job threads for LocateViewer
lockActionBars	4	Whether the action bars should be locked, preventing changes
lodObjectCullDist	1	Lod object culling dist minimum
lodObjectCullSize	1	Lod object culling size
lodObjectFadeScale	1	Lod object fade scale
lodObjectMinSize	1	Lod object min size
lodObjectSizeScale	1	Scales all objects size for culling
lootUnderMouse	4	Whether the loot window should open under the mouse
lossOfControl	4	Enables loss of control spell banner
lossOfControlDisarm	4	Setting for Loss of Control - Disarm
lossOfControlFull	4	Setting for Loss of Control - Full Loss
lossOfControlInterrupt	4	Setting for Loss of Control - Interrupt
lossOfControlRoot	4	Setting for Loss of Control - Root
lossOfControlSilence	4	Setting for Loss of Control - Silence
LowLatencyMinInterval	1	Min frame time (in microseconds) for Low Latency systems. Pass -1 to use monitor's refresh rate.
LowLatencyMode	1	0=None, 1=BuiltIn, 2=Reflex, 3=Reflex+Boost, 4=XeLL
luaErrorExceptions	4	Enable exceptions for non-tainted lua errors
M2ForceAdditiveParticleSort	1	force all particles to sort as though they were additive
M2UseInstancing	1	use hardware instancing
M2UseThreads	1	multithread model animations
majorFactionRenownMap	4	Serialized mapping of faction ID to last known renown rank/level. Updated when the Renown UI is closed, used to control animations in the Major Faction UI.
mapFade	4	Whether to fade out the world map when moving
MaxCharacterComponentLoadStartsPerFrame	1	Maximum number of character component textures to composit per frame - range 1-8
maxFPS	1	Set FPS limit. Min 8
maxFPSBk	1	Set background FPS limit. Min 8
maxFPSLoading	1	Set loading screen max FPS
maxLevelSpecsUsed	4	The specs the player has switched to at max level
maxLightCount	1	Maximum lights to render
maxLightDist	1	Maximum distance to render lights
MaxObservedPetBattles	5	Maximum number of observed pet battles
miniCommunitiesFrame	4	Whether or not the communities frame has been toggled to smaller size
miniDressUpFrame	4	Whether or not the dress up has been toggled to smaller size
minimapInsideZoom	4	The current indoor minimap zoom level
minimapPortalMax	4	Max Number of Portals to traverse for minimap
minimapShapeshiftTracking	4	Stores shapeshift-specific tracking spells that were active last session.
minimapTrackedInfov4	4	Stores the minimap tracking that was active last session.
minimapTrackingClosestOnly	4	If enabled, show only the closest tracked icon for certain minimap icon types.
minimapTrackingShowAll	4	If enabled, show dropdown for configuring all possible minimap tracking options.
minimapZoom	4	The current outdoor minimap zoom level
miniWorldMap	4	Whether or not the world map has been toggled to smaller size
missingTransmogSourceInItemTooltips	4	Whether to show if you have collected the appearance of an item but not from that item itself
motionSicknessFocalCircle	4	Enables a focal circle showing up when mounted
motionSicknessLandscapeDarkening	4	Enables landscape darkening at higher speeds
mountJournalGeneralFilters	4	Bitfield for which collected filters are applied in the mount journal
mountJournalShowPlayer	4	Show the player on the mount preview.
mountJournalSourcesFilter	4	Bitfield for which source filters are applied in the mount journal
mountJournalTypeFilter	4	Bitfield for which type filters are applied in the mount journal
mouseAcceleration	4	-1: use desktop mouse acceleration, 0: disable mouse acceleration, 1: enable mouse acceleration
MouseHiddenInRelativeMode	4	Disabling may work around issues in relative mode in some rare cases
mouseInvertPitch	4	
mouseInvertYaw	4	
mouseSpeed	4	
MoveHistoryEventLog	5	
movePadInPressAndHoldMode	4	When true the MovePad buttons are activated on mouse down and deactivated on mouse up
movePadLocked	4	When false the MovePad can be moved by the player
movieSubtitle	4	Show movie subtitles
movieSubtitleBackground	4	Adds a background to cinematic subtitles -> 1: off, 2: dark, 3: light
movieSubtitleBackgroundAlpha	4	Sets the cinematic subtitles background alpha from 0-100. Default is 70%
MSAAAlphaTest	1	Enable MSAA for alpha-tested geometry
MSAAQuality	1	Multisampling AA quality
nameplateAuraScale	4	Controls the size multiplier for buffs and debuffs on nameplates.
nameplateCheckDistanceForTarget	4	If false, show our target's nameplate even if they're very far away.
nameplateDebuffPadding	4	The padding between the debuff list and the health bar on nameplates.
nameplateForceShowUnitName	4	If true, nameplates will always show the unit name regardless of other unit name settings.
nameplateGameObjectMaxDistance	4	The max distance to show player nameplates for game objects
nameplateMaxAlpha	4	The max alpha of nameplates (when setting alpha based on distance).
nameplateMaxAlphaDistance	4	The distance from the camera that nameplates will reach their maximum alpha.
nameplateMaxDistance	4	The max distance to show nameplates.
nameplateMaxScale	4	The max scale of nameplates.
nameplateMaxScaleDistance	4	The distance from the camera that nameplates will reach their maximum scale.
nameplateMinAlpha	4	The minimum alpha of nameplates (when setting alpha based on distance).
nameplateMinAlphaDistance	4	The distance from the max distance that nameplates will reach their minimum alpha.
nameplateMinScale	4	The minimum scale of nameplates.
nameplateMinScaleDistance	4	The distance from the max distance that nameplates will reach their minimum scale.
nameplateNotSelectedAlpha	4	When you have a target, the alpha of other nameplates (not used if value is negative).
nameplateOccludedAlphaMult	4	Alpha multiplier of nameplates for occluded targets.
nameplateOtherAtBase	4	Position other nameplates at the base, rather than overhead
nameplateOverlapH	4	Percentage amount for horizontal overlap of nameplates
nameplateOverlapV	4	Percentage amount for vertical overlap of nameplates
nameplatePlayerMaxDistance	4	The max distance to show player nameplates.
nameplatePlayRemovalAnimation	4	If true, play a scale/alpha animation when a nameplate is removed. If false, remove the nameplate instantly.
nameplateSelectedAlpha	4	The alpha of the selected nameplate.
nameplateSelectedScale	4	The scale of the selected nameplate.
nameplateShowAll	4	If true, nameplates are shown all the time. If false, nameplates are only shown in combat.
nameplateShowAllPersonalAuras	4	If true, show all personal auras on nameplates, regardless of whether they are normally flagged to be shown.
nameplateShowCastBars	4	Show cast bars for unit nameplates.
nameplateShowClassColor	4	Used to display the class color in enemy nameplate health bars
nameplateShowDebuffsOnFriendly	4	Whether debuffs are shown on friendly nameplates.
nameplateShowEnemies	4	Whether enemy nameplates are shown.
nameplateShowEnemyGuardians	4	Whether enemy guardian nameplates are shown.
nameplateShowEnemyMinions	4	Whether enemy minion nameplates are shown.
nameplateShowEnemyMinus	4	Whether enemy nameplates for entities with a minus sign (indicating they are weaker than the player) are shown.
nameplateShowEnemyPets	4	Whether enemy pet nameplates are shown.
nameplateShowEnemyTotems	4	Whether enemy totem nameplates are shown.
nameplateShowFriendlyClassColor	4	Used to display the class color in friendly nameplate health bars
nameplateShowFriendlyNpcs	4	Whether nameplates are shown for friendly npcs.
nameplateShowFriendlyPlayerGuardians	4	Whether friendly player guardian nameplates are shown.
nameplateShowFriendlyPlayerMinions	4	Whether friendly player minion nameplates are shown.
nameplateShowFriendlyPlayerPets	4	Whether friendly player pet nameplates are shown.
nameplateShowFriendlyPlayers	4	Whether nameplates are shown for friendly players.
nameplateShowFriendlyPlayerTotems	4	Whether friendly player totem nameplates are shown.
nameplateShowFriendlyRealmName	4	Used to show or hide the realm name in friendly player unit nameplate names.
nameplateShowOffscreen	4	When enabled, the nameplate is always shown if owner is in combat with player or player's group member.
nameplateShowOnlyNameForFriendlyPlayerUnits	4	Used to hide every part of the nameplate but the name for friendly player units.
nameplateShowSelf	4	Whether the personal resource display is shown.
nameplateSimplifiedScale	4	Scale used for simplified nameplates.
nameplateSize	4	Provides discrete values that are translated into specific horizontal and vertical scales defined in lua for displaying nameplates.
nameplateStyle	4	Determines how nameplate contents are displayed.
nameplateTargetBehindMaxDistance	4	The max distance to show the target nameplate when the target is behind the camera.
nameplateTargetRadialPosition	4	When target is off screen, position its nameplate radially around sides and bottom. 1: Target Only. 2: All In Combat
nameplateUseClassColorForFriendlyPlayerUnitNames	4	Used to display the class color in friendly player unit nameplate names.
nearclip	1	Near clip plane distance
newDelvesSeason	4	Signals a new delves season for the user, so when they open the companion config UI it shows them a helptip with season info
newMythicPlusSeason	4	Signals a new mythic+ season for the user, so when they open the UI it shows them the info about the season
newPvpSeason	4	Signals a new pvp season for the user, so when they open the UI it shows them the info about the season
noBuffDebuffFilterOnTarget	4	Do not filter buffs or debuffs at all on targets
NonEmitterCombatRange	4	Range to stop shoulder/weapon emissions outside combat
NotchedDisplayMode	1	Do nothing = 0. Shift UI down = 1. Shift everything down = 2.
notifiedOfNewMail	4	Stores whether the player has been previously notified of new mail. Only set to false once everything in their Inbox has been marked as read.
numCurrencyCategories	4	Stores the number of currency categories that existed the last time we logged in
numReputationHeaders	4	Stores the number of reputation headers that existed the last time we logged in
ObjectSelectionCircle	4	
occludedSilhouettePlayer	4	Show a silhouette of your character when obstructed
occlusionMaxJobs	1	Maximum job threads for occlusion render
optOutIngameSurveys	4	Whether we are opted out of receiving surveys.
orderHallMissionTutorial	4	Stores information about which order hall mission tutorials the player has seen
otherRolesAzeriteEssencesHidden	4	Whether to collapse the Azerite Essences for player's other roles
outdoorMinAltitudeDistance	4	Minimum altitude distance for outdoor objects when you are also outdoors before the altitude difference marker displays
Outline	4	Outline Mode
OutlineEngineMode	1	Mode for the OutlineBuffer for the engine
outlineMouseOverFadeDuration	0	
outlineSelectionFadeDuration	0	
outlineSoftInteractFadeDuration	0	
overrideArchive	4	Whether or not the client loads alternate data
overrideScreenFlash	4	Overrides fade color options so that it always fades to black
particleDensity	1	Particle density
particleMTDensity	1	Multi-Tex particle density
particulatesEnabled	1	Particulates enabled
partyBackgroundOpacity	4	The opacity of the party background
partyInvitesCollapsed_Glue	4	The info for pending invites has been shown
Pathing	5	
pathSmoothing	4	NPC will round corners on ground paths
pendingInviteInfoShown	4	The info for pending invites has been shown
perksActivitiesCurrentMonth	4	Current month for perks activities
perksActivitiesLastPoints	4	Last seen number of influence points in the perks progress bar
perksActivitiesPendingCompletion	4	List of completed activities that are pending completion animation in the UI
persistMoveLogOnTransfer	0	Set to 1 to automatically re-enable logging on the current movelog target after a transfer
petJournalFilters	4	Bitfield for which collected filters are applied in the pet journal
petJournalFilterVersion	4	Current filter version. Will reset all filters to their defaults if out of date.
petJournalSort	4	Sorting value for the pet journal
petJournalSourceFilters	4	Bitfield for which source filters are applied in the pet journal
petJournalTab	4	Stores the last tab the pet journal was opened to
petJournalTypeFilters	4	Bitfield for which type filters are applied in the pet journal
petStableShowExoticOnly	4	Filter value for hunter pet stable. Will only show exotic pets in stable if true
petStableSort	4	Sorting value for the hunter pet stable
PhaseHistory	5	
physicsLevel	1	Level of physics world interaction
pingCategoryTutorialShown	4	Has shown the ping category tutorial dialog
pingMode	4	Determines which mode is used to use the ping system.
pingTarget	4	Determines how pinging in the world should behave for the ping system.
playerColorOverrides	4	Any color override values that are different from the default values for an account
PlayerSpawnTracking	5	
playIntroMovie	4	Starting expansion movie to play on startup
plunderstormRealm	6	REALM_ADDRESS to connect to when pressing the Plunderstorm button
POIShiftComplete	0	
portal	6	Name of Battle.net portal to use
PraiseTheSun	4	
PreemptiveCastEnable	5	Enable preemptive triggering of cast visuals based on spell release timing
preloadLoadingDistObject	5	Object preload distance when loading
preloadLoadingDistTerrain	5	Terrain preload distance when loading
preloadPlayerModels	4	Preload all local racial models into memory
preloadStreamingDistObject	5	Object preload distance when streaming
preloadStreamingDistTerrain	5	Terrain preload distance when streaming
PreventOsIdleSleep	10	Enable this to prevent the computer from idle sleeping while the game is running
primaryProfessionsFilter	4	If enabled, primary profession world quests icons will be shown on world maps
ProcDebugEventLog	5	
profanityFilter	4	Whether to enable mature language filtering
professionAccessorySlotsExampleShown	4	If the profession gear slots example has been shown
professionsAllocateBestQualityReagents	4	Indicates if best quality reagents should be automatically allocated in the crafting UI.
professionsAllocateBestQualityReagentsCustomer	4	Indicates if best quality reagents should be automatically allocated in the customer crafting order UI.
professionsFlyoutHideUnowned	4	Boolean indicating if unowned items are hidden in the profession slot flyouts
professionsOrderDurationDropdown	4	The previously selected duration index in the professions customer order form dropdown
professionsOrderRecipientDropdown	4	The previously selected order recipient index in the professions customer order form dropdown
professionToolSlotsExampleShown	4	If the profession gear slots example has been shown
projectedTextures	1	Projected Textures
PushToTalkSound	7	Play a sound when voice recording activates and deactivates
pvpFramesDisplayClassColor	4	Colors pvp frames with the class color
pvpFramesDisplayOnlyHealerPowerBars	4	Whether to display power bars only for healers on Pvp Frames
pvpFramesDisplayPowerBars	4	Whether to display mana, rage, etc. on Pvp Frames
pvpFramesHealthText	4	How to display health text on the pvp frames
pvpOptionDisplayPets	4	Whether to display pets on the pvp frames
pvpSelectedRoles	4	Stores what roles the player will fulfill in a BG.
QuestEventLog	5	
questLogOpen	4	Whether the quest log appears the side of the windowed map.
questPOI	4	If enabled, the quest POI system will be used.
questPOILocalStory	4	Worldmap filter setting for showing any local story quest offers on the map, this is an independent setting for the world map only.
questPOIWQ	4	Worldmap filter setting for showing any WQs on the map, this is in conjunction with the questPOI cvar.
questTextContrast	4	Whether to increase text contrast in Quest UIs
RAIDclusteredShading	1	Allow forward transparent lighting
RAIDcomponentTextureLevel	1	Level of detail for character component textures. 0 means full detail.
RAIDDepthBasedOpacity	1	Raid Enable/Disable Soft Edge Effect
RAIDdoodadLodScale	1	Raid doodad level of detail scale
RAIDentityLodDist	1	Raid Entity level of detail distance
RAIDentityShadowFadeScale	1	Raid Entity shadow fade scale
RAIDfarclip	1	Raid Far clip plane distance
raidFramesCenterBigDefensive	4	Show big defensive raid buffs in the center of the unit frame
raidFramesDispelIndicatorOverlay	4	When showing dispel indicators, also show a color gradient overlay
raidFramesDispelIndicatorOverlayAnimation	4	When showing dispel indicators, use a pulsing alpha anim
raidFramesDispelIndicatorType	4	Choose which dispel icon indicators to show in raid frames
raidFramesDisplayAggroHighlight	4	Whether to display aggro highlights on Raid Frames
raidFramesDisplayBuffs	4	Whether to display buffs on Raid Frames
raidFramesDisplayClassColor	4	Colors raid frames with the class color
raidFramesDisplayDebuffs	4	Whether to display debuffs on Raid Frames
raidFramesDisplayIncomingHeals	4	Whether to display incoming heals on Raid Frames
raidFramesDisplayLargerRoleSpecificDebuffs	4	Show role-specific debuffs as larger on Raid Frames
raidFramesDisplayOnlyDispellableDebuffs	4	Whether to display only dispellable debuffs on Raid Frames
raidFramesDisplayOnlyHealerPowerBars	4	Whether to display power bars only for healers on Raid Frames
raidFramesDisplayPowerBars	4	Whether to display mana, rage, etc. on Raid Frames
raidFramesHealthBarColor	4	Colors raid frame health bars with a custom color if the user doesn't want class colors, ARGB format
raidFramesHealthBarColorBG	4	Colors raid frame backgrounds with a custom color, ARGB format
raidFramesHealthText	4	How to display health text on the raid frames
raidFramesHeight	4	The height of the individual raid frames
raidFramesPosition	4	Where the raid frames should be placed
raidFramesWidth	4	The width of the individual raid frames
raidGraphicsComputeEffects	1	UI value of the raidGraphics setting
raidGraphicsDepthEffects	1	UI value of the raidGraphics setting
raidGraphicsEnvironmentDetail	1	UI value of the raidGraphics setting
raidGraphicsGroundClutter	1	UI value of the raidGraphics setting
raidGraphicsLiquidDetail	1	UI value of the raidGraphics setting
raidGraphicsOutlineMode	1	UI value of the raidGraphics setting
raidGraphicsParticleDensity	1	UI value of the raidGraphics setting
raidGraphicsProjectedTextures	1	UI value of the raidGraphics setting
RAIDgraphicsQuality	5	save for Raid Graphics Quality Selection
raidGraphicsShadowQuality	1	UI value of the raidGraphics setting
raidGraphicsSpellDensity	1	UI value of the raidGraphics setting
raidGraphicsSSAO	1	UI value of the raidGraphics setting
raidGraphicsTextureResolution	1	UI value of the raidGraphics setting
raidGraphicsViewDistance	1	UI value of the raidGraphics setting
RAIDgroundEffectDensity	1	Raid Ground effect density
RAIDgroundEffectDist	1	Raid Ground effect dist
RAIDgroundEffectFade	1	Raid Ground effect fade
RAIDhorizonClip	1	Raid Horizon end distance
RAIDhorizonStart	1	Raid Horizon start distance
RAIDlodObjectCullDist	1	Lod object culling dist minimum
RAIDlodObjectCullSize	1	Lod object culling size
RAIDlodObjectFadeScale	1	Lod object fade scale
RAIDlodObjectMinSize	1	Lod object min size
raidOptionDisplayMainTankAndAssist	4	Whether to display main tank and main assist units in the raid frames
raidOptionDisplayPets	4	Whether to display pets on the raid frames
raidOptionIsShown	4	Whether the Raid Frames are shown
raidOptionKeepGroupsTogether	4	The way to group raid frames
raidOptionLocked	4	Whether the raid frames are locked
raidOptionShowBorders	4	Displays borders around the raid frames.
raidOptionSortMode	4	The way to sort raid frames
RAIDOutlineEngineMode	1	Mode for the OutlineBuffer
RAIDparticleDensity	1	Particle density
RAIDparticleMTDensity	1	Multi-Tex particle density
RAIDParticulatesEnabled	1	Enabling particulates (0-1)
RAIDprojectedTextures	1	Projected Textures
RAIDreflectionMode	1	Reflection mode
RAIDrefraction	1	Refraction
RAIDrippleDetail	1	Ripple surface detail
RAIDsettingsEnabled	1	Raid graphic settings are available
RAIDshadowBlendCascades	1	Blend between shadow cascades (0/1)
RAIDshadowMode	1	Raid Quality of shadows (0-3)
RAIDshadowNumCascades	1	Number of shadow cascades (1-4)
RAIDshadowRt	1	Raid Raytraced shadows (0-2)
RAIDshadowSoft	1	Soft shadows (0/1)
RAIDshadowTextureSize	1	Shadow texture size (1024-2048)
RAIDspellClutter	1	Spell Density
RAIDSSAO	1	Raid Screen-Space Ambient Occlusion
RAIDsunShafts	1	SunShafts
RAIDterrainLodDist	1	Raid Terrain level of detail distance
RAIDTerrainLodDiv	1	Raid Terrain lod divisor
RAIDterrainMipLevel	1	Terrain blend map mip level
RAIDVolumeFog	1	Volume Fog
RAIDVolumeFogLevel	1	Volume Fog Level (0-3)
RAIDWaterDetail	1	Raid Water surface detail
RAIDweatherDensity	1	
RAIDwmoLodDist	1	Raid Wmo level of detail distance
RAIDworldBaseMip	1	World texture base mip
rawMouseEnable	4	Enable raw mouse input
reflectionDownscale	1	Reflection downscale
reflectionMode	1	Reflection mode
refraction	1	Refraction
reloadUIOnAspectChange	1	Reload the UI on aspect change
remoteTextToSpeech	4	Enables typing into a voice chat window to speak to other players using the text to speech system
remoteTextToSpeechVoice	4	Voice option used with Speak for Me where you can send text to speech to other players in voice chat
RenderFormat	1	0 = BGRA8Unorm, 1 = A2BGR10Unorm, 2 = RGBA16F, 3 = RGBA32F
RenderScale	1	Render scale (for supersampling or undersampling)
RenderScaleDowngradeBackgroundMinSize	1	Min size (in pixels) we can reduce render scale to when under high VRAM pressure when the game does not has focus
RenderScaleDowngradeForegroundMinSize	1	Min size (in pixels) we can reduce render scale to when under high VRAM pressure when the game has focus
ReplaceMyPlayerPortrait	4	Replaces local player's unit frame portrait with their class icon
ReplaceOtherPlayerPortraits	4	Replaces other player unit frame portraits with their class icon
reputationsCollapsed	4	List of reputation categories that have been collapsed in the Reputation tab
ResampleAlwaysSharpen	1	Run sharpness pass, even if not using AMD FSR Upscale [0,1]
ResampleQuality	1	Resample quality
ResampleSharpness	1	FSR sharpness strength [0.0-2.0]. 0 is full strength. -1 to disable.
ResizeConstraints	1	0=None,1=AspectRatioLocked,2=DisableResizing
restrictCalendarInvites	4	Whether to restrict calendar invites to friends and guilds only.
rippleDetail	1	Ripple surface detail
rotateMinimap	4	Whether to rotate the entire minimap instead of the player arrow
runeFadeTime	5	Adjust the time the rune fades from on CD to ready
runeSpentFadeTime	5	Adjust the time the base rune takes to fade out after the rune flash fades out
runeSpentFlashTime	5	Adjust the time the rune flash takes to fade out
sceneOcclusionEnable	1	Scene software occlusion
screenEdgeFlash	4	Whether to show a red flash while you are in combat with the world map up
screenshotFormat	1	Set the format of screenshots
screenshotQuality	1	Set the quality of screenshots (1 - 10)
screenshotSizeOverride	1	Set the size of screenshots to a specific resolution (e.g. 7680x4320). 0x0 means use the window size
scriptErrors	4	Whether or not the UI shows Lua errors
scriptProfile	0	Whether or not script profiling is enabled
scriptWarnings	0	Whether or not the UI shows Lua warnings
scrollToLogQuest	4	Whether to scroll to a quest in the quest log when mousing over its map pin
secondaryProfessionsFilter	4	If enabled, secondary profession world quests icons will be shown on world maps
secureAbilityToggle	4	Whether you should be protected against accidentally double-clicking an aura
seenAlliedRaceUnlocks	4	Bit array for which allied race unlocks have been seen
seenAsiaCharacterUpgradePopup	4	Seen the free character upgrade popup (Asia)
seenCharacterUpgradePopup	4	Seen the free character upgrade popup
seenConfigurationWarnings	4	A bitfield to track which configuration warnings have been seen
seenExpansionTrialPopup	4	Seen the expansion trial popup
seenLevelSquishPopup	4	Seen the level squish popup
seenPurchasableClassCapstone	4	Whether or not the player has ever opened the class talent UI and seen a purchasable capstone node
seenRegionalChatDisabled	4	Seen the alert indicating chat has been disabled by default. (UK and CA AADC)
seenTimerunningFirstLoginPopup	4	Seen the timerunning first login popup (value is timerunning season id)
serverAlert	6	Get the glue-string tag for the URL
ServerMessageEventLog	5	
serviceTypeFilter	4	Which trainer services to show
shadowBlendCascades	1	Blend between shadow cascades (0/1)
shadowMode	1	Quality of shadows (0-3)
shadowNumCascades	1	Number of shadow cascades (1-4)
shadowRt	1	Raytraced shadows (0-3)
shadowSoft	1	Soft shadows (0/1)
shadowTextureSize	1	Shadow texture size (1024-2048)
ShakeStrengthCamera	4	Motion sickness control for how much effects can shake the camera
ShakeStrengthUI	4	Motion sickness control for how much effects can shake in 2D UI
shipyardMissionTutorialAreaBuff	4	Stores whether the player has accepted the first area buff mission tutorial
shipyardMissionTutorialBlockade	4	Stores whether the player has accepted the first blockade mission tutorial
shipyardMissionTutorialFirst	4	Stores whether the player has accepted the first mission tutorial
showAllItemsInTransmog	4	Shows all items in the transmogger regardless of armor restrictions
showArenaEnemyCastbar	4	Show the spell enemies are casting on the Arena Enemy frames
showArenaEnemyFrames	4	Show arena enemy frames while in an Arena
showArenaEnemyPets	4	Show the enemy team's pets on the ArenaEnemy frames
showBattlefieldMinimap	4	Whether or not the battlefield minimap is shown
showBuilderFeedback	4	Show animation when building power for builder/spender bar
showCastableBuffs	4	Show only Buffs the player can cast.  Only applies to raids.
showCreateCharacterRealmConfirmDialog	4	Show the character create realm confirmation dialog
showCustomSetDetails	4	Whether or not to show custom set details when the dressing room is opened in maximized mode, default on
showDelveEntrancesOnMap	4	If enabled, delve entrances will display on the world map.
showDispelDebuffs	4	Show only Debuffs that the player can dispel.  Only applies to raids.
showDungeonEntrancesOnMap	4	If enabled, dungeon entrances will display on the world map.
showErrors	0	
showfootprintparticles	1	toggles rendering of footprint particles
showHonorAsExperience	4	Show the honor bar as a regular experience bar in place of rep
showInGameNavigation	4	0: Disable IGN, 1: Enable IGN (Default).
showLoadingScreenTips	4	Show loading screen tooltips
showNPETutorials	4	display NPE tutorials
showOutfitDetails	4	Whether or not to show outfit details when the dressing room is opened in maximized mode, default on
showPartyPets	4	Whether to show pets in the party UI
showPhotosensitivityWarning	4	Showing photosensitivity warning on startup
showPingsInChat	4	Enables ping details being shown in chat.
showPingsOnRaidFrames	4	Enables ping details being shown on raid frames.
showQuestObjectivesInLog	4	Stores whether to show quest objectives in the quest list in the log
ShowQuestUnitCircles	4	Determines if units related to a quest display an indicator on the ground.
showScreenNarrationDialog	4	Show screen narration dialog on startup
showSpectatorTeamCircles	4	Determines if the team color circles are visible while spectating or commentating a wargame
showSpenderFeedback	4	Show animation when spending power for builder/spender bar
showTamers	4	If enabled, pet battle icons will be shown on world maps
showTamersWQ	4	If enabled, WQ pet battle icons will be shown on world maps
showTargetCastbar	4	Show the spell your current target is casting
showTargetOfTarget	4	Whether the target of target frame should be shown
showTempMaxHealthLoss	4	Weather or not to show temporary max health changes on unit health bars
showTimestamps	4	The format of timestamps in chat or "none"
showToastBroadcast	4	Whether to show Battle.net message for broadcasts
showToastClubInvitation	4	Whether to show Battle.net message for club invitations
showToastConversation	4	Whether to show Battle.net message for conversations
showToastFriendRequest	4	Whether to show Battle.net message for friend requests
showToastOffline	4	Whether to show Battle.net message for friend going offline
showToastOnline	4	Whether to show Battle.net message for friend coming online
showToastWindow	4	Whether to show Battle.net system messages in a toast window
showTokenFrame	4	The token UI has been shown
showTutorials	4	display tutorials
showVKeyCastbar	4	If the V key display is up for your current target, show the enemy cast bar with the target's health bar in the game field
showVKeyCastbarOnlyOnTarget	4	
showVKeyCastbarSpellName	4	
simd	5	Enable SIMD features (e.g. SSE)
SkyCloudLOD	1	Texture resolution for clouds
SlugOpticalWeight	0	When rendering, coverage values are remapped to increase the optical weight of the glyphs. This can improve the appearance of small text, but usually looks good only for dark text on a light background.
smoothUnitPhasing	4	The client will try to smoothly switch between the same on model different phases.
smoothUnitPhasingActorPurgatoryTimeMs	4	Time to keep client-actor displays in purgatory before letting go of them, if they were despawned
smoothUnitPhasingAliveTimeoutMs	4	Time to wait for an alive unit to get it's despawn message
smoothUnitPhasingDestroyedPurgatoryTimeMs	4	Time to keep unit displays in purgatory before letting go of them, if they were destroyed
smoothUnitPhasingDistThreshold	4	Distance threshold to active smooth unit phasing.
smoothUnitPhasingEnableAlive	4	Use units that have not despawn yet if they match, in hopes the despawn message will come later.
smoothUnitPhasingUnseenPurgatoryTimeMs	4	Time to keep unit displays in purgatory before letting go of them, if they were just unseen.
smoothUnitPhasingVehicleExtraTimeoutMs	4	Extra time to wait before releasing a vehicle, after it has smooth phased. This allows it's passengers to smooth phase as well.
SoftTargetEnemy	4	Sets when enemy soft targeting should be enabled. 0=off, 1=gamepad, 2=KBM, 3=always
SoftTargetEnemyArc	4	0 = No yaw arc allowance, must be directly in front. 1 = Must be in front yaw arc. 2 = Can be anywhere in tab targeting area.
SoftTargetEnemyRange	4	Max range to soft target enemies (limited to tab targeting range)
SoftTargetForce	4	Auto-set target to match soft target. 1 = for enemies, 2 = for friends
SoftTargetFriend	4	Sets when friend soft targeting should be enabled. 0=off, 1=gamepad, 2=KBM, 3=always
SoftTargetFriendArc	4	0 = No yaw arc allowance, must be directly in front. 1 = Must be in front yaw arc. 2 = Can be anywhere in targeting area.
SoftTargetFriendRange	4	Max range to soft target friends (limited to tab targeting range)
SoftTargetIconEnemy	4	Show icon for soft enemy target
SoftTargetIconFriend	4	Show icon for soft friend target
SoftTargetIconGameObject	4	Show icon for sot interact game objects (interactable objects you cannot normally target)
SoftTargetIconInteract	4	Show icon for soft interact target
SoftTargetInteract	4	Sets when soft interact should be enabled. 0=off, 1=gamepad, 2=KBM, 3=always
SoftTargetInteractArc	4	0 = No yaw arc allowance, must be directly in front. 1 = Must be in front yaw arc. 2 = Can be anywhere in targeting area.
softTargetInteractionTutorialTotalInteractions	4	Total interactions that the player has used in soft targeting
SoftTargetInteractRange	4	Max range to soft target interacts (limited to tab targeting and individual interact ranges)
SoftTargetInteractRangeIsHard	4	Sets if it should be a hard range cutoff, even for something you can interact with right now.
SoftTargetLowPriorityIcons	4	Show interact icons even when there is other visual indicators, such as quest or loot effects
SoftTargetMatchLocked	4	Match appropriate soft target to locked target. 1 = hard locked target only, 2 = for targets you attack
SoftTargetNameplateEnemy	4	Always show nameplates for soft enemy target
SoftTargetNameplateFriend	4	Always show nameplates for soft friend target
SoftTargetNameplateInteract	4	Always show nameplates for soft interact target
SoftTargetNameplateSize	4	Size of soft target icon on nameplate (0 to disable)
softTargettingInteractKeySound	4	Setting for soft targeting that enables sound cues
SoftTargetTooltipDurationMs	4	
SoftTargetTooltipEnemy	4	
SoftTargetTooltipFriend	4	
SoftTargetTooltipInteract	4	
SoftTargetTooltipLocked	4	
SoftTargetWithLocked	4	Allows soft target selection while player has a locked target. 2 = always do soft targeting
SoftTargetWorldtextFarDist	4	
SoftTargetWorldtextNearDist	4	
SoftTargetWorldtextNearScale	4	
SoftTargetWorldtextSize	4	
sortCharListByLastActive	4	Whether to sort the character list by last active time
sortDiskReads	4	Sort async disk reads to minimize seeks (requires restart)
soulbindsActivatedTutorial	4	Bitfield for tutorializing activating soulbinds
soulbindsLandingPageTutorial	4	Boolean indicating if the landing page tutorial has been completed.
soulbindsViewedTutorial	4	Bitfield for tutorializing viewing soulbinds trees
Sound_AllyPlayerHighpassDSPCutoff	7	The cutoff value to use for the Highpass filter on the Ally Player bus (default 80 Hz)
Sound_AlternateListener	7	When enabled, calculates listener forward by simply using the camera's yaw value, instead of a vector from camera position to listener position
Sound_AmbienceHighpassDSPCutoff	7	The cutoff value to use for the Highpass filter on the Ambience bus (default 100 Hz)
Sound_AmbienceVolume	7	Ambience Volume (0.0 to 1.0)
Sound_DialogVolume	7	Dialog Volume (0.0 to 1.0)
Sound_DSPBufferSize	7	sound buffer size, default 0
Sound_EnableAllSound	7	
Sound_EnableAmbience	7	Enable Ambience
Sound_EnableArmorFoleySoundForOthers	7	
Sound_EnableArmorFoleySoundForSelf	7	
Sound_EnableDialog	7	all dialog
Sound_EnableDSPEffects	7	
Sound_EnableEmoteSounds	7	
Sound_EnableEncounterWarningsSounds	7	Enable Encounter Warnings Sounds
Sound_EnableErrorSpeech	7	error speech
Sound_EnableGameplaySFX	7	enables gameplay-specific sfx
Sound_EnableMixMode2	7	test
Sound_EnableMusic	7	Enables music
Sound_EnablePetBattleMusic	7	Enables music in pet battles
Sound_EnablePetSounds	7	Enables pet sounds
Sound_EnablePingSounds	7	Enable Ping Sounds
Sound_EnablePositionalLowPassFilter	7	Environmental effect to make sounds duller behind you or far away
Sound_EnableReverb	7	
Sound_EnableSFX	7	
Sound_EnableSoundWhenGameIsInBG	7	Enable Sound When Game Is In Background
Sound_EncounterWarningsVolume	7	Encounter Warnings Volume (0.0 to 1.0)
Sound_EnemyPlayerHighpassDSPCutoff	7	The cutoff value to use for the Highpass filter on the Enemy Player bus (default 80 Hz)
Sound_GameplaySFX	7	sound volume (0.0 to 1.0)
Sound_ListenerAtCharacter	7	lock listener at character
Sound_MasterVolume	7	master volume (0.0 to 1.0)
Sound_MaxCacheableSizeInBytes	7	Max sound size that will be cached, larger files will be streamed instead
Sound_MaxCacheSizeInBytes	7	Max cache size in bytes
Sound_MusicVolume	7	music volume (0.0 to 1.0)
Sound_NPCHighpassDSPCutoff	7	The cutoff value to use for the Highpass filter on the NPC bus (default 80 Hz)
Sound_NumChannels	7	number of sound channels
Sound_OutputDriverIndex	7	
Sound_OutputDriverName	7	
Sound_OutputSampleRate	7	output sample rate
Sound_PingVolume	7	Ping Volume (0.0 to 1.0)
Sound_SFXVolume	7	sound volume (0.0 to 1.0)
Sound_VoiceChatInputDriverIndex	7	
Sound_VoiceChatInputDriverName	7	
Sound_VoiceChatOutputDriverIndex	7	
Sound_VoiceChatOutputDriverName	7	
Sound_ZoneMusicNoDelay	7	
SoundPerf_VariationCap	7	Limit sound kit variations to cut down on memory usage and disk thrashing on 32-bit machines
SpawnRegion	5	
specular	1	Specular lighting multiplier (0-1)
speechToText	4	Allows enabling transcription on a voice channel in order to see written text based on the words spoken by other players
spellActivationOverlayOpacity	4	The opacity of the Spell Activation Overlays (a.k.a. Spell Alerts)
spellBookHidePassives	4	Stores whether to hide Passive spells in the SpellBook pane
spellBookMinimize	4	Stores whether to always show the the SpellBook pane in half-screen minimized mode
spellClutter	1	Spell Density
SpellCooldownDebugger	5	
spellDiminishPVPEnemiesEnabled	4	Determines if we should show crowd control diminishing returns on enemy unit frames in arenas
spellDiminishPVPOnlyTriggerableByMe	4	Determines if we should show crowd control diminishing returns for all categories or only the ones you could cause with your spells
SpellEventLog	5	
SpellOverrides	5	
SpellQueueWindow	4	Sets how early you can pre-activate/queue a spell/ability. (In Milliseconds)
SpellScriptEventLog	5	
SpellTargeting	5	
spellVisualDensityFilterSetting	4	SVK Density, set by the UI Spell Density setting. 0 - none (dev-only), 1 - minimum, 2 - reduced, 3 - performance, 4 - full
SpellVisuals	5	
SplineOpt	0	toggles use of spline coll optimization
SSAO	1	Screen-Space Ambient Occlusion
ssaoMagicNormals	1	SSAO Use combined GBuffer and face normals; attempts to get the best compromise for architecture, foliage, and characters
ssaoMagicThresholdHigh	1	SSAO High threshold for transitioning from gbuffer to face normal (degrees)
ssaoMagicThresholdLow	1	SSAO Low threshold for transitioning from gbuffer to face normal (degrees)
SSAOType	1	Screen-Space Ambient Occlusion Type
statusText	4	Whether the status bars show numeric health/mana values
statusTextDisplay	4	Whether numeric health/mana values are shown as raw values or percentages, or both
stopAutoAttackOnTargetChange	4	Whether to stop attacking when changing targets
streamingCameraLookAheadTime	1	Look ahead time for streaming.
streamingCameraMaxRadius	1	Max radius of the streaming camera.
streamingCameraRadius	1	Base radius of the streaming camera.
streamStatusMessage	4	Whether to display status messages while streaming content
sunShafts	1	SunShafts
superTrackerDist	4	
SuppressCpuMicrocodeChecks	5	Disables CPU Microcode checks
synchronizeBindings	5	
synchronizeChatFrames	5	
synchronizeConfig	5	
taintLog	0	Controls debug logging of Lua taint and restricted action events to the 'taint.log' file: 0: Disable all logging 1: Log blocked action errors and taint events leading up to them 2: Log tainted reads and writes of global variables 3: Log tainted reads and writes of upvalues 4: Log tainted reads and writes of table fields
taintLogObjectSecrets	0	If enabled, include additional taint log entries when script objects gain secret aspects or values.
talentPointsSpent	4	The player has spent a talent point
TargetAutoEnemy	4	Auto-Target from your single target helpful spells
TargetAutoFriend	4	Auto-Target from your single target helpful spells
TargetAutoLock	4	Lock targets auto-set by the game
TargetEnemyAttacker	4	Auto-Target Enemy when they attack you
targetFPS	1	Set target FPS. Dynamic actions will be taken if you fall below the FPS target
TargetNearestUseNew	4	Use new 7.2 'nearest target' functionality (Set to 0 for 6.x style tab targeting)
TargetPriorityCombatLock	4	1=Lock to in-combat targets when starting from an in-combat target. 2=Further restrict to in-combat with player.
TargetPriorityCombatLockContextualRelaxation	4	1=Enables relaxation of combat lock based on context (eg. no in-combat target infront)
TargetPriorityCombatLockHighlight	4	1=Lock to in-combat targets when starting from an in-combat target. 2=Further restrict to in-combat with player. (while doing hold-to-target)
TargetPriorityPvp	4	When in pvp, give higher priority to players and important pvp targets (1 = players & npc bosses, 2 = all pvp targets, 3 = players only)
telemetryWowlabsPackage	5	The secondary package we want to send telemetry to e.g. Wow_Wowlabs
telemetryWowPackage	5	The primary package we want to send telemetry to e.g. Wow_Mainline or Wow_Classic
teleportMaxNoLoadDist	1	Max teleport distanace without preload
terrainLodDist	1	Terrain level of detail distance
TerrainLodDiv	1	Terrain lod divisor
terrainMipLevel	1	Terrain blend map mip level
test_cameraDynamicPitch	4	Adjust camera pitch according to zoom distance for a more cinematic view
test_cameraDynamicPitchBaseFovPad	4	Fraction of screen height to keep feet below
test_cameraDynamicPitchBaseFovPadDownScale	4	Strength of dynamic pitch when looking down
test_cameraDynamicPitchBaseFovPadFlying	4	Fraction of screen height to keep character below when able to fly
test_cameraDynamicPitchSmartPivotCutoffDist	4	Dynamic pitch disables Smart Pivot within this camera distance
test_cameraHeadMovementDeadZone	4	
test_cameraHeadMovementFirstPersonDampRate	4	
test_cameraHeadMovementMovingDampRate	4	
test_cameraHeadMovementMovingStrength	4	
test_cameraHeadMovementRangeScale	4	
test_cameraHeadMovementStandingDampRate	4	
test_cameraHeadMovementStandingStrength	4	
test_cameraHeadMovementStrength	4	
test_cameraOverShoulder	4	
test_cameraTargetFocusEnemyEnable	4	
test_cameraTargetFocusEnemyStrengthPitch	4	
test_cameraTargetFocusEnemyStrengthYaw	4	
test_cameraTargetFocusInteractEnable	4	
test_cameraTargetFocusInteractStrengthPitch	4	
test_cameraTargetFocusInteractStrengthYaw	4	
textLocale	4	Set the game locale for text
textToSpeech	4	Reads chat text out loud using the voice text to speech system based on the selected options
textureErrorColors	1	If enabled, replaceable textures that aren't specified will be purple
textureFilteringMode	1	Texture filtering mode
ThreadPoolLimitHP	10	Limit num threads for High prio jobs
ThreadPoolLimitLP	10	Limit num threads for Low prio jobs
ThreadPoolLimitMP	10	Limit num threads for Mid prio jobs
ThreadPoolPerThreadAllocator	10	0=Disabled, 1=Allow, 2=Force (around 12% faster but uses ~300MB more memory)
threatPlaySounds	4	Whether or not to sounds when certain threat transitions occur
threatShowNumeric	4	Whether or not to show numeric threat on the target and focus frames
threatWarning	4	Whether or not to show threat warning UI (0 = off, 1 = in dungeons, 2 = in party/raid, 3 = always)
threatWorldText	4	Whether or not to show threat floaters in combat
timeMgrAlarmEnabled	4	Toggles whether or not the time manager's alarm will go off
timeMgrAlarmMessage	4	The time manager's alarm message
timeMgrAlarmTime	4	The time manager's alarm time in minutes
timeMgrUseLocalTime	4	Toggles the use of either the realm time or your system time
timeMgrUseMilitaryTime	4	Toggles the display of either 12 or 24 hour time
titleBarShortName	5	
titleBarShowAccountName	5	
titleBarShowBuildInfo	5	
titleBarShowCharacterName	5	
titleBarShowConfigName	5	
titleBarShowGxInfo	5	
titleBarShowPID	5	
titleBarShowRealmName	5	
toastDuration	4	How long to display Battle.net toast windows, in seconds
tooltipShowAuraSpellIDs	4	Show spell IDs in tooltips for unit auras.
toyBoxCollectedFilters	4	Bitfield for which collected filters are applied in the toybox
toyBoxExpansionFilters	4	Bitfield for which expansion filters are applied in the toybox
toyBoxSourceFilters	4	Bitfield for which source filters are applied in the toybox
trackedAchievements	4	Internal cvar for saving tracked achievements in order
trackedInitiativeTasks	4	Internal cvar for saving tracked initiative tasks in order
trackedPerksActivities	4	Internal cvar for saving tracked perks activities in order
trackedProfessionRecipes	4	Internal cvar for saving tracked recipes in order
trackedProfessionRecraftRecipes	4	Internal cvar for saving tracked recraft recipes in order
trackedQuests	4	Internal cvar for saving automatically tracked quests in order
trackedWorldQuests	4	Internal cvar for saving automatically tracked world quests
transmogCurrentSpecOnly	4	Stores whether transmogs apply to current spec instead of all specs
transmogDebug	4	Enables Transmog Debug Logging
transmogHideIgnoredSlots	4	Whether ignored slots display as hidden or unassigned in the transmog frame
transmogPreviewedWeaponToggle	4	Whether the transmog ModelScene should show the MH/OH combo or the RangedWeapon
transmogrifySetsFilters	4	Bitfield for which transmog sets filters are applied in the transmog sets tab
transmogrifyShowCollected	4	Whether to show collected transmogs in the at the transmogrifier
transmogrifyShowUncollected	4	Whether to show uncollected transmogs in the at the transmogrifier
transmogrifySourceFilters	4	Bitfield for which source filters are applied in the  wardrobe at the transmogrifier
transmogShowID	4	Shows the itemModifiedAppearanceID or setID in transmog tooltips
TTSUseCharacterSettings	5	If character-specific TTS settings are being used.
TurnSpeed	5	Set the keyboard turn rate in degrees per second; capped by the server
UberTooltips	4	Show verbose tooltips
uiScale	4	The current UI scale
uiScaleMultiplier	4	A multiplier for the default UI scale. -1=determine based on system/monitor DPI, 0.5-2.0=multiplier to use when calculating UI scale. Only applied when useUIScale is 0.
unitClutter	4	Enables/Disables unit clutter
unitClutterInstancesOnly	4	Whether or not to use unit clutter in instances only (0 or 1)
unitClutterPlayerThreshold	4	The number of players that have to be nearby to trigger unit clutter
UnitEnterCombatLog	5	
unitFacingPlayerDeadZoneDeg	4	Degrees outside a unit's default facing a player has to be for the unit to face them on interact
UnitNameEnemyGuardianName	4	
UnitNameEnemyMinionName	4	
UnitNameEnemyPetName	4	
UnitNameEnemyPlayerName	4	
UnitNameEnemyTotemName	4	
UnitNameFocused	4	
UnitNameForceHideMinus	4	
UnitNameFriendlyGuardianName	4	
UnitNameFriendlyMinionName	4	
UnitNameFriendlyPetName	4	
UnitNameFriendlyPlayerName	4	
UnitNameFriendlySpecialNPCName	4	
UnitNameFriendlyTotemName	4	
UnitNameGuildTitle	4	
UnitNameHostleNPC	4	
UnitNameInteractiveNPC	4	
UnitNameNonCombatCreatureName	4	
UnitNameNPC	4	
UnitNameOwn	4	
UnitNamePlayerGuild	4	
UnitNamePlayerPVPTitle	4	
unitsLookAtPlayers	4	Enables units turning their head to look at players
UnitVisibility	5	
unlockedMajorFactions	4	Internal cvar for tracking unlocked Major Factions. Used to play a toast when a new faction has been unlocked.
useBLEEP	6	Client override to always prefer BLEEP, when available
useCommentatorSelectionCircles	4	Determines whether to use the commentator selection circles or the default selection circles while spectating or commentating a wargame
useHighResTextures	4	Prefer upscaled versions of texture assets when available
useIPv6	6	Enable the usage of IPv6 sockets
UseKeyHeldSpellErrorPollTime	4	(Internal only) Time between a failed cast and when it should attempt to cast again in ms. (Clamped to 100 and 10000)
useMaxFPS	1	Enables or disables FPS limit
useMaxFPSBk	1	Enables or disables background FPS limit
userFontScale	4	in-game: Defines the scale of the font used in places around the UI where readability requires larger defaults which are still customizable by the user.
userFontScaleGlue	4	glues: Defines the scale of the font used in places around the UI where readability requires larger defaults which are still customizable by the user.
useShadowMapping	1	Use shadow mapping
UseSlug	0	Render with slug text
useTargetFPS	1	Enables or disables the target FPS
useUiScale	4	Whether or not the UI scale should be used
validateFrameXML	4	Display warning when FrameXML detects unparsed elements
VerboseSpellScriptEventLog	5	
videoOptionsVersion	1	Video options version
videoOptionsVersionDefault	1	
violenceLevel	4	Sets the violence level of the game
VoiceChatMasterVolumeScale	7	Voice Chat audio ducking, applied as a scale to the game's master volume when somebody is speaking in voice chat
VoiceCommunicationMode	7	Which communication mode to use for voice chat: push-to-talk, open mic, etc...
VoiceEnableWhenGameIsInBG	7	Enable Voice Chat when game is in background
VoiceInputDevice	7	Which deviceID you would like to use to pick up the sound of your wonderful voice, usually a microphone of some kind, empty string is system default
VoiceInputVolume	7	The gain applied to your microphone, helps change your speaking volume from other users' perspectives, larger values are louder.
VoiceOutputDevice	7	Which deviceID you would like to use to transmit the sound of other users' wonderful voices, usually a speakers of some kind, empty string is system default
VoiceOutputVolume	7	The volume of incoming voice chat, how loud other users' voices sound
VoicePushToTalkKeybind	7	Push to talk key
VoiceSelfDeafened	7	Voice Chat Self Deafened
VoiceSelfMuted	7	Voice Chat Self Muted
VoiceVADSensitivity	7	How sensitive voice activity detection is.  Value ranges from 0 to 100, smaller values will transmit at a lower noise threshold.
volumeFog	1	Volume Fog
volumeFogDisableLightScattering	1	0: vf point light scattering enabled. 1: disabled
volumeFogDisableNoise	1	0: vf noise enabled. 1: noise disabled
volumeFogDisableShadows	1	0: vf shadows enabled. 1: shadows disabled
volumeFogInterior	1	Volume Fog Interiors
volumeFogLevel	1	Volume Fog Level (0-3)
volumeFogUse16BitTexture	1	0: 8 bit. 1: 16 bit. REQUIRES gxRestart
vrsParticles	1	Render scale like effect for particles. Only used if lots of particles are on screen
vrsValar	1	Generate a shading rate mask based on velocity and luminance. Requires VRS Tier 2.
vrsValarAlwaysOn	1	Use VRS even when not GPU bound
vrsValarEnvLuma	1	Env. Luma for VALAR
vrsValarGPUMode	1	0 - Auto-detect, 1 - Standard (discrete GPU default), 2 - Low Power (integrated GPU default) modes for VALAR
vrsValarLPUseCornerSampling	1	Use corner sampling for VALAR Low Power
vrsValarUseAsyncCompute	1	Use async compute for VALAR
vrsValarUseMotionVectors	1	Use motion vectors for VALAR
vrsValarUseWeberFechner	1	Use Weber-Fechner Algo for VALAR
vrsValarWeberFechnerConstant	1	Weber-Fechner Constant for VALAR
vrsWorldGeo	1	Render scale like effect for terrain, buildings and liquids
vsync	1	vsync on or off
WalkableSurfacesValidationLog	5	
wardrobeSetsFilters	4	Bitfield for which transmog sets filters are applied in the wardrobe in the collection journal
wardrobeShowAllFactions	4	Stores whether to show both Alliance and Horde transmogs in the Wardrobe
wardrobeShowAllRaces	4	Stores whether to show race restricted transmogs in the Wardrobe
wardrobeShowCollected	4	Whether to show collected transmogs in the wardrobe
wardrobeShowUncollected	4	Whether to show uncollected transmogs in the wardrobe
wardrobeSourceFilters	4	Bitfield for which source filters are applied in the wardrobe in the collection journal
waterDetail	1	Water surface detail
weatherDensity	1	
webChallengeURLTimeout	5	How long to wait for the web challenge URL (in seconds). 0 means wait forever.
whisperMode	4	The action new whispers take by default: "popout", "inline", "popout_and_inline"
wholeChatWindowClickable	4	Whether the user may click anywhere on a chat window to change EditBox focus (only works in IM style)
wmoDoodadDist	1	Wmo doodad load distance
wmoLodDist	1	Wmo level of detail distance
wmoLodDistScale	1	Wmo level of detail distance scale
wmoPortalFadeScale	1	Wmo portal fade scale
wmoPortalInteriorFade	1	Wmo portal interior fade
WorldActionsLog	5	
worldBaseMip	1	World texture base mip
worldIntersectMaxJobs	1	Maximum job threads for culling
worldLoadSort	1	Sort objects by distance when loading
worldMapShowCursorCoords	4	Show cursor coordinates on the world map
worldMapShowPlayerCoords	4	Show player coordinates on the world map
worldPreloadHighResTextures	1	Require high res textures to be loaded in streaming non critical radius when preloading
worldPreloadNonCritical	1	Require objects to be loaded in streaming non critical radius when preloading
worldPreloadNonCriticalTimeout	1	World preload time (in seconds) when non-critical items are automatically ignored
worldPreloadSort	1	Sort objects by distance when preloading
worldQuestFilterAnima	4	If enabled, world quests with anima rewards will be shown on the map
worldQuestFilterArtifactPower	4	If enabled, world quests with artifact power rewards will be shown on the map
worldQuestFilterEquipment	4	If enabled, world quests with equipment rewards will be shown on the map
worldQuestFilterGold	4	If enabled, world quests with gold rewards will be shown on the map
worldQuestFilterProfessionMaterials	4	If enabled, world quests with profession material rewards will be shown on the map
worldQuestFilterReputation	4	If enabled, world quests with reputation rewards will be shown on the map
worldQuestFilterResources	4	If enabled, world quests with order resource rewards or war resource rewards will be shown on the map
WorldTextCritScreenY_v2	4	
WorldTextGravity_v2	4	
WorldTextMinAlpha_v2	4	
WorldTextMinSize	4	Smallest size used for world text like player names
WorldTextNonRandomZ_v2	4	
WorldTextRampDuration_v2	4	
WorldTextRampPow_v2	4	
WorldTextRampPowCrit_v2	4	
WorldTextRandomXY_v2	4	
WorldTextRandomZMax_v2	4	
WorldTextRandomZMin_v2	4	
WorldTextScale_v2	4	
WorldTextScreenY_v2	4	
WorldTextStartPosRandomness_v2	4	
worldViewCullMaxJobs	1	Maximum job threads for culling
xpBarText	4	Whether the XP bar shows the numeric experience value
]==]
