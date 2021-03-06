local sys = require("sys")

-- 项目信息,预留
PROJECT = "playit" -- W600 on LuatOS
VERSION = "1.0.0"
PRODUCT_KEY = "1234567890"

-- 日志TAG, 非必须
local TAG = "main"

sys.subscribe("WLAN_READY", function ()
    print("!!! wlan ready event !!!")
    -- 马上进行时间同步
    socket.ntpSync()
end)

----------------------------------------------------------------------
-- 对接SSD1306, 当前显示一行就好了
function display_str(str)
    disp.clear()
    disp.drawStr(str, 1, 18)
    disp.update()
end

-- 初始化显示屏
log.info(TAG, "init ssd1306")
disp.init("ssd1306")
display_str("Booting ...")

-- 配网回调
sys.subscribe("WLAN_PW_RE", function(ssid, password)
    if ssid then
        log.info(TAG, "airkiss GOT", ssid, password)
        local conf = {ssid=ssid,password=password}
        local jdata = json.encode(conf)
        if jdata ~= nil then
            log.info(TAG, "save to conf.json", jdata)
            local f = io.open("/conf.json", "w")
            f:write(jdata)
            f:close()
        end
    else
        log.info(TAG, "airkiss fail")
    end
end)

-- wifi连接的回调, 这时候还没获取ip, socket不可用
sys.subscribe("WLAN_STA_CONNECTED", function(re)
    if re == 1 then
        log.info(TAG, "wifi connect ok, wait for ip")
        display_str("Connect wifi OK")
    else
        log.info(TAG, "wifi connect fail")
        display_str("Connect wifi FAIL")
    end
end)

-- wifi就绪,已获取ip, socket可用
sys.subscribe("WLAN_READY", function(re)
    log.info(TAG, "wifi is ready, ip ready")
    display_str("wifi is ready")
end)

-- 联网主流程
sys.taskInit(function()
    wlan.setMode("wlan0", wlan.STATION)
    -- 看看有没有配网信息, 保存在config.json里面
    local f = io.open("/conf.json")
    log.info(TAG, "conf.json", f)
    if f ~= nil then
        log.info(TAG, "reading config.json")
        local str = f:read()
        f:close()
        log.info(TAG, "config.json", str)
        local conf,result,errinfo = json.decode(str)
        log.info(TAG, "config.json", conf, result, errinfo)
        if result then
            local ssid = conf["ssid"]
            local password = conf["password"]
            log.info(TAG, "wifi info in config.json", ssid, password)
            if ssid then
                display_str("Connecting to " .. ssid)
                wlan.connect(ssid, password)
                return
            else
                log.info(TAG, "no ssid in config.json")
            end
        else
            log.info(TAG, "config.json NOT JSON", errinfo)
        end
    else
        log.info(TAG, "/config.json not exist")
    end
    -- 没有配网信息, 开始airkiss配网
    while wlan.ready() ~= 1 do
        log.info(TAG, "begin airkiss ...")
        display_str("begin airkiss ...")
        wlan.airkiss_start()
        sys.waitUntil("WLAN_PW_RE", 180*1000)
        sys.wait(5000)
    end
end)

-- 业务流程, 联网后定时发送温度数据到服务器
sys.taskInit(function()
    while 1 do 
        if wlan.ready() == 1 then
            sys.wait(1000)
            log.info("ds18b20", "start to read ds18b20 ...")
            local temp = (sensor.ds18b20(28) or "")
            log.info("ds18b20", "TEMP: ", temp, os.date())
            display_str("Temp: " .. temp  .. " rssi:" .. tostring(wlan.rssi()))
            local t = {"GET /api/w60x/report/ds18b20?mac=", wlan.get_mac(), "&temp=", temp, " HTTP/1.0\r\n",
                    "Host: site0.cn\r\n",
                    "User-Agent: LuatOS/0.1.0\r\n",
                        "\r\n"}
            --local data = table.concat(t)
            --print(data)
            -- TODO: 改成socket/netc对象
            socket.tsend("site0.cn", 80, table.concat(t))
            log.info("network", "tsend complete, sleep 5s")
            sys.wait(5000)
        else
            log.warn("main", "wlan is not ready yet")
            sys.waitUntil("WLAN_READY", 30000)
        end
    end
end)

-- TODO: 用户按钮(PB7), 用于清除配网信息,重新airkiss

-- TODO: 联网更新脚本和底层(也许)

-- 主循环, 必须加
sys.run()
