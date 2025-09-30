-- Local variables
-- Lua script stays in memory for the lifetime of the Fluent Bit process,
-- so all local variables persist across filter calls.

local DELAY_SEC = 300 -- Delay (in seconds) before flushing logs
local buckets = {} -- Table to bucket logs by their timestamp (seconds)
local earliest_sec = nil -- Tracks the earliest second we have in our buckets table
local last_processed_second = nil -- Tracks which second we last ran the flush logic on

-- Lua Filter function
function log_delay(tag, ts_table, record)
    -- Current time in integer seconds
    local now_sec = os.time()
    local now_floor = now_sec  
    local arrival_sec = ts_table.sec or 0
    if earliest_sec == nil or arrival_sec < earliest_sec then
        earliest_sec = arrival_sec
    end

    -- 1) Insert the new record into its bucket
    if not buckets[arrival_sec] then
        buckets[arrival_sec] = {}
    end
    table.insert(buckets[arrival_sec], record)

    -- 2) Check if we've already processed this second
    if last_processed_second == now_floor then
        -- Skip the flush; Return no output
        return 2, ts_table, {}
    end

    -- 3) Otherwise, do the flush logic once for this second
    last_processed_second = now_floor
    local to_emit = {}

    -- Flush all buckets whose second <= (now_sec - DELAY_SEC)
    while earliest_sec and earliest_sec <= (now_sec - DELAY_SEC) do
        local bucket_logs = buckets[earliest_sec]
        if bucket_logs then
            -- Use table.move to quickly merge bucket_logs into to_emit
            -- (start index = 1, end index = #bucket_logs, insert destination = #to_emit+1)
            table.move(bucket_logs, 1, #bucket_logs, #to_emit + 1, to_emit)
            buckets[earliest_sec] = nil
        end

        -- Move on to the next second
        earliest_sec = earliest_sec + 1
    end

    -- 4) Return any flushed logs
    if #to_emit == 0 then
        return 2, ts_table, {}
    else
        local new_ts = { sec = now_sec, nsec = 0 }
        return 1, new_ts, to_emit
    end
end
