module CmdArgs where


import System.Environment (getArgs)
import Data.Maybe


parseArgs :: IO (Maybe (Int, [(String, Int)], Int))
parseArgs = do
    argz <- getArgs
    let procId   = parseProcId argz
    let ipPorts  = parseIpsPorts $ drop 1 argz
    let msgCount = parseMessagesCount $ drop 11 argz

    if (isNothing procId || isNothing ipPorts || isNothing msgCount) 
        then 
            putStrLn "Error parsing arguments!" >> return Nothing 
        else
            return $ Just (fromJust procId, fromJust ipPorts, fromJust msgCount)

    -- let mProcId = maybeRead (head argz) :: Maybe Int
    -- case mProcId of 
    --  Just procId -> do
    --      let list = parseIpsPorts $ drop 1 argz
    --      return $ Just (procId, list)
    --  otherwise -> do
    --      putStrLn "Error parsing args: invalid process id (arg #0)!"
    --      return Nothing


parseProcId :: [String] -> Maybe Int
parseProcId argz =
    Nothing


parseIpsPorts :: [String] -> Maybe [(String, Int)]
parseIpsPorts argz =
    Nothing
    

parseMessagesCount :: [String] -> Maybe Int
parseMessagesCount argz =
    Nothing


-- | Parses a String into Just a or into Nothing
--
-- For example, to obtain an Int from a stdin line,
--
-- > line <- getLine
-- > let res = (maybeRead line :: Maybe Int)
--
-- > case res of
-- >    Just v  -> *do something with the Int v*
-- >    Nothing -> ...
maybeRead :: Read a => String -> Maybe a
maybeRead val = fmap fst . listToMaybe . reads $ val
