module Nifty.DeliveryGuard where


import qualified Data.Set               as S


data DeliveryGuard = DeliveryGuard
    { upperLimit        :: Integer
    , outliers          :: S.Set (Integer)
    }

instance Show DeliveryGuard where
    show DeliveryGuard {upperLimit = u, outliers = o} =
        "DG: {" ++ show u ++ ", " ++ show (S.size o) ++ "}"


newDeliveryGuard ::
    DeliveryGuard
newDeliveryGuard =
    DeliveryGuard { upperLimit = 0, outliers = S.empty }


canDeliver ::
    DeliveryGuard
    -> Integer
    -> (Bool, DeliveryGuard)
canDeliver guard value =
    if value <= (upperLimit guard)
        then (False, guard)
        else if S.member value (outliers guard)
            then (False, guard)
            else if (value - 1) == (upperLimit guard)
                then (True, newGuardULimit)
                else (True, newGuardOutlier)
    where
        newGuardULimit = continueCompaction guard { upperLimit = value }
        newGuardOutlier = compactGuardWithValue guard value

canDeliverRange ::
    DeliveryGuard
    -> Integer
    -> Integer
    -> (Bool, DeliveryGuard)
canDeliverRange guard low high =
    if high <= (upperLimit guard)
        then (False, guard)
        else if S.member low (outliers guard)
            then (False, guard)
            else if (low - 1) == (upperLimit guard)
                then (True, newGuardULimit)
                else (True, newGuardOutlier)
    where
        newGuardULimit = continueCompaction guard { upperLimit = high }
        newGuardOutlier = expandOutliers guard low high


expandOutliers ::
    DeliveryGuard
    -> Integer
    -> Integer
    -> DeliveryGuard
expandOutliers g l h =
    if l <= h
        then expandOutliers g {outliers = xOutl} (l+1) h
        else g
    where
        xOutl = S.insert l (outliers g)


isDelivered ::
    DeliveryGuard
    -> Integer
    -> Bool
isDelivered guard value =
    if  (value <= (upperLimit guard))
        || S.member value (outliers guard)
        then True
        else False


compactGuardWithValue ::
    DeliveryGuard
    -> Integer
    -> DeliveryGuard
compactGuardWithValue guard value =
    if value == newLimit
        then continueCompaction guard {upperLimit = newLimit}
        else if S.member newLimit (outliers guard)
                then compactGuardWithValue newGuardCompacted value
                else guard {outliers = expandOutl}
    where
        newLimit = (upperLimit guard) + 1
        compactOl = S.delete newLimit (outliers guard)
        expandOutl = S.insert value (outliers guard)
        newGuardCompacted = guard {upperLimit = newLimit, outliers = compactOl}


continueCompaction ::
    DeliveryGuard
    -> DeliveryGuard
continueCompaction guard =
    if S.member newLimit (outliers guard)
        then continueCompaction newGuardCompacted
        else guard
    where
        newLimit = (upperLimit guard) + 1
        compactOl = S.delete newLimit (outliers guard)
        newGuardCompacted = guard {upperLimit = newLimit, outliers = compactOl}