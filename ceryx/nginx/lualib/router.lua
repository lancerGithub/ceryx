local host = ngx.var.host

-- Check if key exists in local cache
local cache = ngx.shared.ceryx
local res, flags = cache:get(host)
if res then
    ngx.var.container_url = res
    return
end

local redis = require "resty.redis"
local red = redis:new()
red:set_timeout(100) -- 100 ms
local redis_host = os.getenv("CERYX_REDIS_HOST")
if not redis_host then redis_host = "127.0.0.1" end
local redis_port = os.getenv("CERYX_REDIS_PORT")
if not redis_port then redis_port = 6379 end
local redis_password = os.getenv("CERYX_REDIS_PASSWORD")
if not redis_password then redis_password = nil end
local res, err = red:connect(redis_host, redis_port)

-- Return if could not connect to Redis
if not res then
    return ngx.exit(ngx.HTTP_BAD_GATEWAY)
end

if redis_password then
    local res, err = red:auth(redis_password)
    if not res then
        ngx.ERR("Failed to authenticate Redis: ", err)
        return
    end
end

-- Construct Redis key
local prefix = os.getenv("CERYX_REDIS_PREFIX")
if not prefix then prefix = "ceryx" end
local key = prefix .. ":routes:" .. host

-- Try to get target for host
res, err = red:get(key)
if not res or res == ngx.null then
    -- Construct Redis key for $wildcard
    key = prefix .. ":routes:$wildcard"
    res, err = red:get(key)
    if not res or res == ngx.null then
        return ngx.exit(ngx.HTTP_BAD_GATEWAY)
    end
    ngx.var.container_url = res
    return
end

-- Save found key to local cache for 5 seconds
cache:set(host, res, 5)

ngx.var.container_url = res
