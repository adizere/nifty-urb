module URB where



startURB :: (Int, [(String, Int)], Int) -> IO ()
startURB (procId, ipsPorts, msgCoount) = do
	return ()