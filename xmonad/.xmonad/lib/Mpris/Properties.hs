{-# LANGUAGE OverloadedStrings #-}
module Mpris.Properties
       ( getPosition
       , getStatus
       , getMetadata
       , getAuthor
       , getUrl
       , getTitle
       , getLength
       , Metadata
       , PlayerStatus(..)
       ) where

import DBus
import DBus.Client

import Data.Int (Int64)
import Data.Map as M

import Mpris.Utils

getProperty :: Client -> String -> String -> IO MethodReturn
getProperty client name property =
  call_ client (methodCall "/org/mpris/MediaPlayer2" "org.freedesktop.DBus.Properties" "Get")
    { methodCallDestination = Just (busName_ name)
    , methodCallBody = [ toVariant ("org.mpris.MediaPlayer2.Player" :: String),
                         toVariant property ]
    }

getPosition :: Client -> String -> IO Integer
getPosition client name = do
  reply <- getProperty client name "Position"
  return . fromIntegral $ ((unpack . unpack . head . methodReturnBody $ reply) :: Int64)

data PlayerStatus = Playing | Paused | Stopped deriving (Eq, Show)

getStatus :: Client -> String -> IO PlayerStatus
getStatus client name = do
  reply <- getProperty client name "PlaybackStatus"
  return $ case ((unpack . unpack . head . methodReturnBody $ reply) :: String) of
    "Playing" -> Playing
    "Stopped" -> Stopped
    "Paused"  -> Paused
    _         -> Stopped

type Metadata = Map String Variant

getMetadata :: Client -> String -> IO Metadata
getMetadata client destination = do
  reply <- getProperty client destination "Metadata"
  return ((unpack . unpack $ head (methodReturnBody reply)) :: Map String Variant)

-- | Get author
getAuthor :: Metadata -> Maybe String
getAuthor m = case M.lookup "xesam:artist" m of
  Just x  -> Just $ head (unpack x)
  Nothing -> Nothing

getTitle :: Metadata -> Maybe String
getTitle m = case M.lookup "xesam:title" m of
  Just x  -> Just $ unpack x
  Nothing -> Nothing

getUrl :: Metadata -> Maybe String
getUrl m = case M.lookup "xesam:url" m of
  Just x  -> Just $ unpack x
  Nothing -> Nothing

getLength :: Metadata -> Integer
getLength m = case M.lookup "mpris:length" m of
  -- UGLY!!! For some reason we can't deserialize the variant returned
  -- from spotify... so we parse the string representation instead
  Just x  -> let printed = show x
                 number = read . drop 8 $ printed
             in number :: Integer
  Nothing -> 1
