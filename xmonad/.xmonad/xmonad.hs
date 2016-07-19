import Control.Monad (when)
import Data.Monoid (All(..))
import Data.Maybe (isJust, fromJust)
import Data.Foldable (forM_)
import DBus.Mpris
import System.Exit (exitSuccess)
import System.IO (hPutStrLn)
import System.IO.Strict as IOS (readFile)
import XMonad
import XMonad.Actions.CycleWS (toggleWS)
import XMonad.Actions.CycleWindows (cycleRecentWindows)
import XMonad.Hooks.DynamicLog (dynamicLogWithPP, ppOutput)
import XMonad.Hooks.EwmhDesktops (ewmh, fullscreenEventHook)
import XMonad.Hooks.ManageDocks (docksEventHook, ToggleStruts (..))
import XMonad.Hooks.SetWMName (setWMName)
import XMonad.Hooks.UrgencyHook (withUrgencyHook, NoUrgencyHook (..))
import XMonad.Prompt.RunOrRaise (runOrRaisePrompt)
import XMonad.Prompt.Window (windowPromptGoto)
import XMonad.Util.EZConfig (additionalKeys, additionalKeysP)
import XMonad.Util.ExtensibleState as XS
import XMonad.Util.Run (spawnPipe, runInTerm, safeSpawn)
import qualified XMonad.StackSet as W

import qualified Constants as C
import MPD
import Utils
import StackSetExtra as WX
import Workspaces
import PulseAudio
import Interactive
import Brightness
import Mount
import Mpris
import IdoFile

-- TODO: we might want to set urgency for the "to be focused" window in the future.
-- TODO: test that the window sending the event is in fact the firefox
-- window.  So far, this hasn't caused any trouble
-- | This fixes the annoying issue where opening a link from an
-- outside application focuses firefox.
withoutNetActiveWindow :: XConfig a -> XConfig a
withoutNetActiveWindow c = c { handleEventHook = \e -> do
                                  p <- case e of
                                        ClientMessageEvent { ev_message_type = mt } -> do
                                          a_aw <- getAtom "_NET_ACTIVE_WINDOW"
                                          return (mt /= a_aw)
                                        _ -> return True
                                  if p then handleEventHook c e else return (All True) }

propertyHook :: XMonad.Event -> X All
propertyHook e = do
  case e of
    PropertyEvent { ev_atom = atom
                  , ev_window = window
                  , ev_propstate = st } -> do
      root <- theRoot `fmap` ask
      a <- getAtom "MPRIS_CURRENT_ACTIVE_DBUS"
      when (window == root && atom == a && st == propertyNewValue) $ do
        d <- display `fmap` ask
        dat <- getStringProperty d window "MPRIS_CURRENT_ACTIVE_DBUS"
        forM_ dat Mpris.resetCurrent
  return (All False)

main :: IO ()
main = do
  w <- IOS.readFile "/home/matus/.whereami"
  let (left, middle, right) = case w of
              "brno" -> (2,0,1)
              "home" -> (2,1,0)
              "logio" -> (2,0,1)
              _ -> (2,0,1)
  let (S xmobarScreen) = case w of
                    "brno" -> right
                    "home" -> left
                    "logio" -> middle
                    _ -> middle
  xmproc <- spawnPipe $ "/home/matus/.cabal/bin/xmobar -x " ++ show xmobarScreen ++ " /home/matus/.xmonad/xmobarrc"
  xmonad $
    (\c -> c { startupHook = do
                  root <- theRoot `fmap` ask
                  d <- display `fmap` ask
                  liftIO $ selectInput d root $ substructureRedirectMask .|. substructureNotifyMask .|. enterWindowMask .|. leaveWindowMask .|. structureNotifyMask .|. buttonPressMask .|. propertyChangeMask
                  XS.put (Workspaces.ScreenOrder [left, middle, right])
                  startupHook c
                  setWMName "LG3D" }) $
    withoutNetActiveWindow $
    ewmh $
    withUrgencyHook NoUrgencyHook defaultConfig
           {
             -- <geekosaur> given the limitations of client message
             -- events currently, I would consider using a root window
             -- property for communication because you get full
             -- control over the message format instead of the
             -- hardwired one the X11 binding uses for clientMessage
             -- events
             -- <geekosaur> then in handleEventHook you can look for
             -- PropertyNotify events and check if the property that
             -- changed is the one you are using
             -- <geekosaur> and maybe the best part: you would have to
             -- write a program to send a custom clientMessage, but
             -- you can use xprop -root -set for the root window
             -- property (admittedly it's ugly to use)

             manageHook         = C.manageHook
           , layoutHook         = C.layout
           , logHook            = dynamicLogWithPP C.printer { ppOutput = hPutStrLn xmproc }
           , handleEventHook    = propertyHook <+> fullscreenEventHook <+> docksEventHook
           , modMask            = mod4Mask
           , borderWidth        = 1
           , terminal           = "urxvtc"
           , normalBorderColor  = "#000000"
           , focusedBorderColor = "#008800"
           , workspaces         = C.workspaces
           } `additionalKeysP`
           [ ("<XF86AudioPlay>", Mpris.toggleCurrent)
           , ("<XF86AudioStop>", Mpris.stopCurrent)
           , ("<XF86AudioPrev>", Mpris.previousCurrent)
           , ("<XF86AudioNext>", Mpris.nextCurrent)
           , (leader <%> "t",        Mpris.switch)
           , (leader <%> "s",        Mpris.stopCurrent)
           , (leader <%> "p",        Mpris.previousCurrent)
           , (leader <%> "<Backspace>", Mpris.stopCurrent >> Mpris.toggleCurrent)
           , (leader <%> "<Delete>", Mpris.nextCurrent)
           , (leader <%> "<Print>",  Mpris.toggleCurrent)
           , (leader <%> "d",        MPD.deleteCurrent)
           , (leader <%> "c",        MPD.clear)
           , (leader <%> "<F9>",     MPD.playPlaylist Clear >>= whenJust_ (mpd DBus.Mpris.play))
           , (leader <%> "<F10>",    MPD.playArtist Clear >>= whenJust_ (mpd DBus.Mpris.play) )
           , (leader <%> "<F11>",    MPD.playDirectory Clear >>= whenJust_ (mpd DBus.Mpris.play))
           , (leader <%> "u" <%> "<F9>",  MPD.playPlaylist Add >>= whenJust_ (mpd DBus.Mpris.play))
           , (leader <%> "u" <%> "<F10>", MPD.playArtist Add >>= whenJust_ (mpd DBus.Mpris.play))
           , (leader <%> "u" <%> "<F11>", MPD.playDirectory Add >>= whenJust_ (mpd DBus.Mpris.play))
           , (leader <%> "<F12>",   MPD.jumpToTrack >>= whenJust_ (mpd DBus.Mpris.play))
           , ("<XF86AudioRaiseVolume>", paIncreaseVolumeRunning)
           , ("<XF86AudioLowerVolume>", paDecreaseVolumeRunning)
           , ("<XF86AudioMute>",        spawn "amixer -q -D pulse sset Master toggle")
           , (leader <%> "<Left>", decBrightness)
           , (leader <%> "<Right>", incBrightness)
           , (leader <%> "b", setBrightness)
           , (leader <%> "m", muteSinkInput)
           , (leader <%> "v", setVolumeSinkInput)
           , (leader <%> "<Insert>",    spawn "amixer -q -D pulse sset Master toggle")
           , (leader <%> "<F7>",        spawn "/home/matus/bin/toggle-touchpad")
           , (leader <%> "o", mountDevice)
           , (leader <%> "S-o", umountDevice)
           , ("M4-S-<Return>", runInTerm "" "fish")
           , ("<XF86Sleep>", spawn "sudo pm-suspend")
           , ("<Print>" <%> "<Print>", spawn "/home/matus/bin/take-screenshot")
           , ("<Print>" <%> "u" <%> "<Print>", spawn "/home/matus/bin/take-screenshot noupload")
           , (leader <%> "<F1>" <%> "<F1>", spawn "xfce4-settings-manager")
           , (leader <%> "<F1>" <%> "<F2>", spawn "xfce4-appfinder")
             -- create a submap for these
           , (leader <%> "=" <%> "a", runInTermOrRaise "alsamixer" "0")
           , (leader <%> "=" <%> "p", runInTermOrRaise "pacmixer" "0")
           , (leader <%> "=" <%> "n", runInTermOrRaise "ncmpcpp" "0")
           , (leader <%> "=" <%> "c", runInTermOrRaise "pavucontrol" "0")
           , (leader <%> "=" <%> "t", do
               Just file <- myIdoFilePrompt "/home/matus/download/"
               safeSpawn "xdg-open" [file]
             )
           , ("M2-<Backspace>", toggleWS)
           , ("M2-S-<Pause>", io exitSuccess)
           , ("M2-<Pause>", recompileXMonad)
           , ("M2-p", runOrRaisePrompt C.prompt)
           , (leader <%> leader, windowPromptGoto C.prompt)
           , ("M2-c", kill)
           , ("M2-m", withScreen left W.view)
           , ("M2-,", withScreen middle W.view)
           , ("M2-.", withScreen right W.view)
           , ("M2-C-m", withScreen left WX.shiftAndView)
           , ("M2-C-,", withScreen middle WX.shiftAndView)
           , ("M2-C-.", withScreen right WX.shiftAndView)
           , ("M2-M4-m", withScreen left WX.shiftAndGreedyView)
           , ("M2-M4-,", withScreen middle WX.shiftAndGreedyView)
           , ("M2-M4-.", withScreen right WX.shiftAndGreedyView)
           , ("M2-S-m", withScreen left W.shift)
           , ("M2-S-,", withScreen middle W.shift)
           , ("M2-S-.", withScreen right W.shift)
           , ("M2-/", windows WX.shiftToOtherScreen)
           , ("M4-p", windows W.focusDown)
           , ("M4-n", windows W.focusUp)
           , ("M4-P", windows W.swapDown)
           , ("M4-N", windows W.swapUp)
           , ("M2-[", windows W.focusDown)
           , ("M2-]", windows W.focusUp)
           , ("M2-=", cycleRecentWindows [xK_Alt_R] xK_equal xK_minus)
           , ("M4-b", sendMessage ToggleStruts)
           , ("M4-S-b", broadcastMessage ToggleStruts >> refresh)
           , (leader <%> "=" <%> "o", inotify)
           , (leader <%> "=" <%> "i", inotify2)
           , (leader <%> "=" <%> "u", urxvtc)
           , (leader <%> "=" <%> "m", iMWindow)
           -- TODO: pridat "hide all" a "show all"
           ] `additionalKeys`
           (
             [ (mod2Mask,                   W.greedyView)
             , (mod4Mask,                   W.greedyView)
             , (shiftMask .|. mod2Mask,   W.shift)
             , (shiftMask .|. mod4Mask,   W.shift)
             , (controlMask .|. mod2Mask, WX.shiftAndGreedyView)
             , (mod4Mask .|. mod2Mask,    WX.shiftAndView)
             ]
             >>= uncurry C.withWorkspacesD
           ) `additionalKeys`
           (
             [ ((mod2Mask .|. mod5Mask, xK_0), paSetVolumeRunning "100%") ] ++
             [ ((mod2Mask .|. mod5Mask, key), paSetVolumeRunning $ show (10 * i) ++ "%") | (key, i) <- zip [xK_1 .. xK_9] [1..]]
           )
    where
      leader = "<Pause>"
      mpd = Mpris.switchTo "org.mpris.MediaPlayer2.mpd"

-- brno letisko LKTB
-- sliac letisko LZSL
-- http://www.airports-worldwide.info/index.php?page=airport
