local shrexpect = require "libs.shrexpect"
local slogger = {}

---@alias ssd.libs.slogger.LogTarget fun(s:string)

---@enum ssd.libs.slogger.Level
slogger.levels = {
    FATAL = 1,
    ERROR = 2,
    WARN = 3,
    INFO = 4,
    DEBUG = 5,
    TRACE = 6
}

---@param side string
---@param fn string
function slogger.new(side, fn)
    shrexpect({ "string", "string" }, { side, fn })
    assert(fs.open(fn, "w")).close()
    ---@type table<ssd.libs.slogger.LogTarget>
    local targets = {}
    ---@class ssd.libs.slogger.LogProvider
    local provider = {}
    ---@type string[]
    local writeBuffer = {}
    local filter = slogger.levels.TRACE
    ---@param f ssd.libs.slogger.Level
    function provider.setFilter(f)
        filter = f
    end

    local function log(level, name, s)
        if level > filter then return end
        local time = math.floor(os.clock() * 20)
        local ns =
            ("(%s)[%5s][%s:%s]: %s"):format(time, level, side, name, s)
        for v in pairs(targets) do
            v(ns)
        end
        writeBuffer[#writeBuffer + 1] = ns
    end

    ---@param target ssd.libs.slogger.LogTarget
    function provider.addTarget(target)
        targets[target] = target
    end

    function provider.logger(name)
        ---@class ssd.libs.slogger.Logger
        local logger = {}

        ---@param level string
        ---@param s string
        function logger.log(level, s)
            log(level, name, s)
        end

        ---@param level string
        ---@param s string
        ---@param ... any
        function logger.flog(level, s, ...)
            logger.log(level, s:format(...))
        end

        ---@param s string
        function logger.info(s)
            logger.log("INFO", s)
        end

        ---@param s string
        ---@param ... any
        function logger.finfo(s, ...)
            logger.flog("INFO", s, ...)
        end

        ---@param s string
        function logger.warn(s)
            logger.log("WARN", s)
        end

        ---@param s string
        ---@param ... any
        function logger.fwarn(s, ...)
            logger.flog("WARN", s, ...)
        end

        ---@param s string
        function logger.error(s)
            logger.log("ERROR", s)
        end

        ---@param s string
        ---@param ... any
        function logger.ferror(s, ...)
            logger.flog("ERROR", s, ...)
        end

        ---@param s string
        function logger.debug(s)
            logger.log("DEBUG", s)
        end

        ---@param s string
        ---@param ... any
        function logger.fdebug(s, ...)
            logger.flog("DEBUG", s, ...)
        end

        return logger
    end

    function provider.flush()
        local s = table.concat(writeBuffer, "\n")
        writeBuffer = {}
        local f = assert(fs.open(fn, "a"))
        f.write(s .. "\n")
        f.close()
    end

    function provider.thread()
        while true do
            sleep(10)
            if #writeBuffer > 0 then
                provider.flush()
            end
        end
    end

    return provider
end

return slogger
