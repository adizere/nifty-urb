module Main where


import CmdArgs (parseArgs)
import Nifty.URB (startURB)

import Data.Maybe
import System.Posix.Signals (installHandler, Handler(Catch), sigINT, sigTERM, sigUSR1)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)
import Control.Concurrent (forkIO)
import System.Exit (exitSuccess)


stopHandler :: MVar (Int) -> IO ()
stopHandler stopMVar = do
    -- putStrLn "Signal caught.. program will exit"
    putMVar stopMVar 1


startHandler :: MVar (Int) -> IO ()
startHandler startMVar = do
    putMVar startMVar 1


main :: IO ()
main = do
    startMVar <- newEmptyMVar
    stopMVar  <- newEmptyMVar
    _ <- installHandler sigINT (Catch $ stopHandler stopMVar) Nothing
    _ <- installHandler sigTERM (Catch $ stopHandler stopMVar) Nothing
    _ <- installHandler sigUSR1 (Catch $ startHandler startMVar) Nothing
    _ <- forkIO (parseArgs >>= startWithArgs startMVar)
    takeMVar stopMVar >> exitSuccess


startWithArgs :: MVar (Int) -> (Maybe (Int, [(String, Int)], Int)) -> IO ()
startWithArgs startMVar urbArgs
    | isJust urbArgs = startURB (fromJust urbArgs) startMVar
    | otherwise      = return ()