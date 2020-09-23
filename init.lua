dofile('config.lua')
dofile('sensor.lua')
dofile('mqtt.lua')

local version = "v1.0.0"
local sensor_name = 'aqs-' .. node.chipid()



print('Connecting to network... (60 sec timeout)')
-- restart the sensor in case network connection can not be established for more than 60 seconds
tmr.softwd(60) 
local wifi_conf = {
  ssid = config.wifi_ssid,
  pwd = config.wifi_pwd,
  connect_cb = function(ret)
    print('Connected to ' .. ret.SSID .. ' on channel ' .. ret.channel)
  end,

  disconnect_cb = function(ret) 
    print('Disconnected from ' .. ret.SSID)
    node.restart() -- TODO maybe use a timer and reconnect instead of restarting the sensor
  end,

  got_ip_cb = function(ret) 
    print('Wifi Connection successfully established')
    print('Ip: ' .. ret.IP)
    print('Netmask: ' .. ret.netmask)
    print('Default Gateway: ' .. ret.gateway)

    do_mqtt_connect()
  end
}
if wifi.getmode() ~= wifi.STATION then
  wifi.setmode(wifi.STATION)
end

wifi.sta.sethostname(sensor_name)
wifi.sta.config(wifi_conf)



print('Creating MQTT client...')
local m = mqtt.Client(sensor_name, 120)
local availability_topic = mqtt_topic('sensor/%s/status', sensor_name)
m:lwt(availability_topic, 'offline', 1, 1)

function do_mqtt_connect()
  print('Connecting to MQTT broker...')
  m:connect(config.mqtt_host, config.mqtt_port, false, handle_mqtt_success, handle_mqtt_error)
end

function handle_mqtt_success(client)
  print('Successfully connected to MQTT broker\nPublishing Sensor information...')
  local state_topic = mqtt_topic('sensor/%s/state', sensor_name)
  local device_descriptor = string.format([[{
    "connections": [ ["mac", "%s"] ],
    "identifiers": ["%s"],
    "manufacturer": "Winsen Electronics",
    "model": "ZH03B",
    "name": "ZH03B Dust Detector",
    "sw_version": "%s"
  }]], wifi.sta.getmac(), node.chipid(), version)

  local ha_conf = function(name, field, uom)
    if not uom then uom = '' end
    return string.format([[{ 
      "device": %s,
      "unique_id": "%s-%s", 
      "name": "%s", 
      "state_topic": "%s", 
      "avty_t": "%s",
      "qos": 1, 
      "unit_of_measurement": "%s", 
      "value_template": "{{ value_json.%s}}" 
    }]], device_descriptor, sensor_name, field, name, state_topic, availability_topic, uom, field)
  end
  
  -- Create a sensor for each measurement
  -- 1.0 micron PM concentration
  client:publish(mqtt_topic('sensor/%s-pm1_0/config', sensor_name), ha_conf('PM 1.0', 'pm1_0', 'µg/m3'), 1, 1)
  -- 2.5 micron PM concentration
  client:publish(mqtt_topic('sensor/%s-pm2_5/config', sensor_name), ha_conf('PM 2.5', 'pm2_5', 'µg/m3'), 1, 1)
  -- 10 micron PM concentration
  client:publish(mqtt_topic('sensor/%s-pm10/config', sensor_name), ha_conf('PM 10', 'pm10', 'µg/m3'), 1, 1)
  -- 2.5 micron AQI index
  client:publish(mqtt_topic('sensor/%s-aqi2_5/config', sensor_name), ha_conf('AQI PM 2.5', 'aqi2_5'), 1, 1)
  -- 10 micron AQI index
  client:publish(mqtt_topic('sensor/%s-aqi10/config', sensor_name), ha_conf('AQI PM 10', 'aqi10'), 1, 1)

  -- Initialize the sensor with the measurement callback
  zh03:init(function(reading)
    local payload = string.format([[{ 
      "pm1_0": %d, 
      "pm2_5":  %d, 
      "pm10": %d,
      "aqi2_5": %d,
      "aqi10": %d
    }]], reading.pm1_0, reading.pm2_5, reading.pm10, reading.aqi2_5, reading.aqi10)
    client:publish(state_topic, payload, 1, 0)
    -- restart the device if no new sensor measurement for more than 10 seconds
    tmr.softwd(10)
  end)

  -- mark sensor online
  client:publish(availability_topic, 'online', 1, 1)
end

function handle_mqtt_error(client, reason)
  print('Failed to connect to MQTT broker, reason: ' .. reason .. ' (Retry in 5 seconds)')
  tmr.create():alarm(5 * 1000, tmr.ALARM_SINGLE, do_mqtt_connect)
end
