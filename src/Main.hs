module Main where


import CmdArgs (parseArgs)
import URB (startURB)

import Data.Maybe
import System.Posix.Signals (installHandler, Handler(Catch), sigINT, sigTERM)
import Control.Concurrent.MVar (tryTakeMVar, MVar, newEmptyMVar, putMVar)
import Control.Concurrent (threadDelay)
import System.IO (hFlush, stdout)



handler :: MVar (Int) -> IO ()
handler s_interrupted = do
    putStrLn "Signal caught.. program will exit"
    putMVar s_interrupted 1


main :: IO ()
main = do
    s_interrupted <- newEmptyMVar
    _ <- installHandler sigINT (Catch $ handler s_interrupted) Nothing
    _ <- installHandler sigTERM (Catch $ handler s_interrupted) Nothing
    putStrLn "heueue"
    urbArgs <- parseArgs
    if isNothing urbArgs
        then return () 
        else do
            startURB $ fromJust urbArgs
    recvFunction s_interrupted


recvFunction :: MVar (Int) -> IO ()
recvFunction mi = do
    putStrLn "Waiting.. "
    threadDelay 1000000
    hFlush stdout
    mv <- tryTakeMVar mi
    case mv of 
        Just val -> do
            putStrLn $ "W: Interrupt Received. Killing the process."
            hFlush stdout
            return ()
        Nothing -> recvFunction mi