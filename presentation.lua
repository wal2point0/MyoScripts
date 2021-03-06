-- Modified version of com.thalmic.scripts.presentation
-- Adds variable speed scrolling based on angle of arm when accompanied with gesture.
scriptId = 'com.janek.scripts.presentation'

-- Effects

function forward()
    if useLeftRight then
        myo.keyboard("right_arrow", "press")
    else
        myo.keyboard("down_arrow", "press")
    end
end

function backward()
    if useLeftRight then
        myo.keyboard("left_arrow", "press")
    else
        myo.keyboard("up_arrow", "press")
    end
end

function space()
    myo.keyboard("space", "press")
end

-- Burst forward or backward depending on the value of shuttleDirection.
function shuttleBurst()
    if currentPoseEdge[1] == "fingersSpread" then
        space()
    elseif shuttleDirection == "forward" then
        forward()
    elseif shuttleDirection == "backward" then
        backward()
    end
end

-- Helpers

-- Makes use of myo.getArm() to swap wave out and wave in when the armband is being worn on
-- the left arm. This allows us to treat wave out as wave right and wave in as wave
-- left for consistent direction. The function has no effect on other poses.
function conditionallySwapWave(pose)
    if myo.getArm() == "left" then
        if pose == "waveIn" then
            pose = "waveOut"
        elseif pose == "waveOut" then
            pose = "waveIn"
        end
    end
    return pose
end

-- Makes use of myo.getXDirection() to swap the angle when the armband is being worn with the x-axis
-- facing the wrist. This allows us to use the same sign comparisons when using the angle, no matter
-- which way it is being worn.
function conditionallySwapAngle(angle)
    if myo.getXDirection() == "towardWrist" then
        return angle * -1
    end
    return angle
end

-- Adjusts which angle direction is considered 'faster' based on which way we are scrolling, which is
-- determined from the pose.
function getPoseMultiplier(pose)
    if pose == "waveIn" then
        return -1
    end
    return 1
end

-- Unlock mechanism

function unlock()
    unlocked = true
    extendUnlock()
end

function extendUnlock()
    unlockedSince = myo.getTimeMilliseconds()
end

-- Implement Callbacks

function onPoseEdge(pose, edge)
    -- myo.debug("pose: " .. pose)
    currentPoseEdge = {pose, edge}
    -- Unlock
    if pose == "thumbToPinky" then
        if edge == "off" then
            -- Unlock when pose is released in case the user holds it for a while.
            unlock()
        elseif edge == "on" and not unlocked then
            -- Vibrate twice on unlock.
            -- We do this when the pose is made for better feedback.
            myo.vibrate("short")
            myo.vibrate("short")
            extendUnlock()
        end
    end

    -- Forward/backward and shuttle.
    if pose == "waveIn" or pose == "waveOut" or pose == "fingersSpread" then
        local now = myo.getTimeMilliseconds()
        initialPoseAngle = conditionallySwapAngle(myo.getRoll())

        if unlocked and edge == "on" then
            -- Deal with direction and arm.

            pose = conditionallySwapWave(pose)

            -- Determine direction based on the pose.
            if pose == "waveIn" then
                shuttleDirection = "backward"
            else
                shuttleDirection = "forward"
            end

            -- Initial burst and vibrate
            myo.vibrate("short")
            shuttleBurst()

            -- Set up shuttle behaviour. Start with the longer timeout for the initial
            -- delay.
            shuttleSince = now
            shuttleTimeout = SHUTTLE_CONTINUOUS_TIMEOUT
            extendUnlock()
        end
        -- If we're no longer making wave in or wave out, stop shuttle behaviour.
        if edge == "off" then
            shuttleTimeout = nil
        end
    end
end

-- All timeouts in milliseconds.

-- Time since last activity before we lock
-- UNLOCKED_TIMEOUT = 2200
UNLOCKED_TIMEOUT = 10000

-- Delay when holding wave left/right before switching to shuttle behaviour
SHUTTLE_CONTINUOUS_TIMEOUT = 600

-- How often to trigger shuttle behaviour
SHUTTLE_CONTINUOUS_PERIOD = 300

-- Delta we use to change the shuttle speed based on Roll (angle w/respect to x-axis)
SHUTTLE_SPEED_DELTA = 20

-- A global variable used by functions other than onPoseEdge to identify the current pose
currentPoseEdge = {nil, nil}

useLeftRight = false

function onPeriodic()
    local now = myo.getTimeMilliseconds()

    -- Shuttle behaviour
    if shuttleTimeout then
        extendUnlock()

        -- Changed radians to degrees just for my own comfort.
        angleDelta = 180 * (conditionallySwapAngle(myo.getRoll()) - initialPoseAngle) / math.pi

        -- If we haven't done a shuttle burst since the timeout, do one now
        if (now - shuttleSince) > shuttleTimeout then

            --  Perform a shuttle burst
            shuttleBurst()

            -- Update the timeout. (The first time it will be the longer delay.)
            shuttleTimeout = SHUTTLE_CONTINUOUS_PERIOD + getPoseMultiplier(currentPoseEdge[1]) * angleDelta * SHUTTLE_SPEED_DELTA

            -- Update when we did the last shuttle burst
            shuttleSince = now
        end
    end

    -- Lock after inactivity
    if unlocked then
        -- If we've been unlocked longer than the timeout period, lock.
        -- Activity will update unlockedSince, see extendUnlock() above.
        if myo.getTimeMilliseconds() - unlockedSince > UNLOCKED_TIMEOUT then
            unlocked = false
        end
    end
end

function onForegroundWindowChange(app, title)
    -- myo.debug("title: " .. title)
    -- Here we decide if we want to control the new active app.
    local wantActive = false
    activeApp = ""
    useLeftRight = false

    if platform == "MacOS" then
        if app == "com.apple.iWork.Keynote" then
            -- Keynote on MacOS
            wantActive = true
            activeApp = "Keynote"
        elseif app == "com.microsoft.Powerpoint" then
            -- Powerpoint on MacOS
            wantActive = true
            activeApp = "Powerpoint"
        elseif app == "com.adobe.Reader" then
            -- Adobe Reader on MacOS
            wantActive = true
            activeApp = "Adobe Reader"
        elseif app == "com.apple.Preview" then
            -- Preview on MacOS
            wantActive = true
            activeApp = "Preview"
        end
    elseif platform == "Windows" then
        -- Powerpoint on Windows
        wantActive = string.match(title, " %- PowerPoint$") or
                     string.match(title, "^PowerPoint Slide Show %- ") or
                     string.match(title, " %- PowerPoint Presenter View$")
        if wantActive then
            activeApp = "Powerpoint"
        elseif string.match(title, "%- Adobe Reader$") then
            wantActive = true
            activeApp = "Adobe Reader"        
        elseif string.match(title, "%- OpenOffice Impress$") then
            wantActive = true
            activeApp = "OpenOffice Impress"
        elseif string.match(title, "%- Windows Photo Viewer$") then
            wantActive = true
            activeApp = "Windows Photo Viewer"
            useLeftRight = true
        elseif string.match(title, "Photo Viewer Slide Show") then
            wantActive = true
            activeApp = "Photo Viewer Slide Show"
            useLeftRight = true
        end
    end
    return wantActive
end

function activeAppName()
    -- Return the active app name determined in onForegroundWindowChange
    return activeApp
end

function onActiveChange(isActive)
    if not isActive then
        unlocked = false
    end
end