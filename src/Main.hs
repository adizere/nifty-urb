module Main where


import System.Posix.Signals (installHandler, Handler(Catch), sigINT, sigTERM)
import Control.Concurrent.MVar (tryTakeMVar, MVar, newEmptyMVar, putMVar)
import Control.Concurrent (threadDelay)
import System.IO (hFlush, stdout)


handler :: MVar (Int) -> IO ()
handler s_interrupted = do
    putStrLn "Caught!"
    putMVar s_interrupted 1


main :: IO ()
main = do
    s_interrupted <- newEmptyMVar
    _ <- installHandler sigINT (Catch $ handler s_interrupted) Nothing
    _ <- installHandler sigTERM (Catch $ handler s_interrupted) Nothing
    putStrLn "heueue"
    recvFunction s_interrupted

      
recvFunction :: MVar (Int) -> IO ()
recvFunction mi = do
    putStrLn "Waiting.. "
    threadDelay 1000000
    hFlush stdout
    mv <- tryTakeMVar mi
    case mv of 
        Just val -> do
            putStrLn $ "W: Interrupt Received. Killing Server" ++ (show val)
            hFlush stdout
            return ()
        Nothing -> recvFunction mi