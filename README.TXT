# Everything is managed by cabal-install, so install it
# Note: sudo needed for these steps

sudo apt-get update
sudo apt-get install cabal-install

# Update the local repository index
cabal update

# Then install all the needed libraries using cabal
# For this, we have to be in the same directory as the project
cd /home/user/nifty-urb/
cabal configure

# And install the dependencies; this might take a while..
cabal install --only-dependencies

# Now we should be able to build everything
cabal configure
cabal build

# Finally, we can run the executable
# Use the da_proc wrapper:
./da_proc 1 127.0.0.1 9991 127.0.0.1 9992 127.0.0.1 9993 127.0.0.1 9994 127.0.0.1 9995 -1 &
./da_proc 2 127.0.0.1 9991 127.0.0.1 9992 127.0.0.1 9993 127.0.0.1 9994 127.0.0.1 9995 -1 &
./da_proc 3 127.0.0.1 9991 127.0.0.1 9992 127.0.0.1 9993 127.0.0.1 9994 127.0.0.1 9995 -1 &
./da_proc 4 127.0.0.1 9991 127.0.0.1 9992 127.0.0.1 9993 127.0.0.1 9994 127.0.0.1 9995 -1 &
./da_proc 5 127.0.0.1 9991 127.0.0.1 9992 127.0.0.1 9993 127.0.0.1 9994 127.0.0.1 9995 -1 &