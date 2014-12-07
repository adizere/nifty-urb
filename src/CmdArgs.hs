module CmdArgs where


import System.Environment (getArgs)
import Data.Maybe


parseArgs :: IO (Maybe (Int, [(String, Int)], Int))
parseArgs = do
    argz <- getArgs
    let procId   = parseProcId argz
    let ipPorts  = parseIpsPorts (drop 1 argz) []
    let msgCount = parseMessagesCount $ drop 11 argz

    putStrLn $ "this proc has id " ++ (show procId)
    putStrLn $ "all procs info " ++ (show ipPorts)
    putStrLn $ "message count " ++ (show msgCount)

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
    maybeRead (head argz)


parseIpsPorts :: [String] -> [(String, Int)] -> Maybe [(String, Int)]
parseIpsPorts argz accum
    | length accum == 5 = Just $ reverse accum
    | isJust newPort    = parseIpsPorts (drop 2 argz) 
                                        ((newIp, fromJust newPort):accum)
    | otherwise         = Nothing
    where
        (newIpList, newPortString) = splitAt 1 argz
        newIp = head newIpList
        newPort = maybeRead (head newPortString) :: Maybe Int


parseMessagesCount :: [String] -> Maybe Int
parseMessagesCount argz =
    maybeRead (head argz)


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
