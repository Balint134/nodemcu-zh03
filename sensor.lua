-- ZH03 Sensor API
zh03 = {}
-- doing zh03.debug = true on the console will turn on debug mode with additional logging
zh03.debug = false
-- In case something went sideways, enter ERR state
zh03.ERR = -1
-- Sensor is in SLEEP mode
zh03.SLEEP = 1
-- Sensor is ACTIVE
zh03.ACTIVE = 2
-- Last measurement value from the sensor, table contents:
-- pm2_5, pm10, pm1_0
zh03.last_measure = { pm2_5 = 0, pm10 = 0, pm1_0 = 0, aqi2_5 = 0, aqi10 = 0 }
-- Current sensor state
zh03.state = zh03.ERR
-- last data microseconds
zh03.last_data = 0

-- Init sensor
function zh03:init(on_measure)
  if not self.isInit then
    self.uart = softuart.setup(9600, config.uart_tx, config.uart_rx)
  end

  print('Initializing Sensor\nUsing sUART (TX: D2, RX: D3) for particle sensor')
  self.uart:on('data', 24, function(str)
    local now = tmr.now()
    local data = { str:byte(1, -1) }

    print('Received data after ' .. (now - self.last_data) .. 'uS')
    self.last_data = now

    if self.debug then dump(data) end
    if not chkvalid(data) then
      print('ERR: Failed to checksum frame')
      self.state = self.ERR
      return
    end

    if data[1] == 0x42 and data[2] == 0x4D then
      -- data[high_byte] << 8 | data[low_byte]
      self.last_measure.pm1_0 = bit.bor(bit.lshift(data[11], 8), data[12])
      self.last_measure.pm2_5 = bit.bor(bit.lshift(data[13], 8), data[14])
      self.last_measure.pm10 = bit.bor(bit.lshift(data[15], 8), data[16])

      self.last_measure.aqi2_5 = calc_aqi2_5(self.last_measure.pm2_5)
      self.last_measure.aqi10 = calc_aqi10(self.last_measure.pm10)
      
      self.state = self.ACTIVE
      if on_measure then 
        on_measure(self.last_measure)
      end
      print('OnData callback took ' .. tmr.now() - now .. ' us')
    end
  end)

  self.uart:write(string.char(0xFF, 0x01, 0x78, 0x40, 0x00, 0x00, 0x00, 0x00, 0x47))
  self.isInit = true
end

-- Initiate a sensor suspend
function zh03:suspend()
  -- send suspend request
  self.uart:write(string.char(0xFF, 0x01, 0xA7, 0x01, 0x00, 0x00, 0x00, 0x00, 0x57))
  self.state = self.SLEEP
end

function zh03:resume()
  -- send resume request
  self.uart:write(string.char(0xFF, 0x01, 0xA7, 0x00, 0x00, 0x00, 0x00, 0x00, 0x58))
end

function dump(data) 
  if not data then
    print('nil')
    return
  end
  if type(data) == 'table' then
    local str = '['
    for i,v in ipairs(data) do
        str = str .. string.format("0x%x", v) .. ', '
    end
    str = str .. ']'
    print(str)
  else
    print(type(data) .. ': ' .. data)
  end
end

function chkvalid(data)
  if #data < 2 then
    return false
  end

  -- checksum = data[last - 1] << 8 | data[last]
  local checksum = bit.bor(bit.lshift(data[#data - 1], 8), data[#data])
  local val = 0x0
  for i = 1, #data - 2 do
    val = val + data[i]
  end

  return val == checksum
end

-- source: https://www.airnow.gov/aqi/aqi-calculator-concentration/
function calc_aqi2_5(pm)
  local aqi
  if pm >= 0 and pm < 12.1 then
    aqi = linear_scale(50, 0, 12, 0, pm)
  elseif pm >= 12.1 and pm < 35.5 then
    aqi = linear_scale(100, 51, 35.4, 12.1, pm)
  elseif pm >= 35.5 and pm < 55.5 then
    aqi = linear_scale(150, 101, 55.4, 35.5, pm)
  elseif pm >= 55.5 and pm < 150.5 then
    aqi = linear_scale(200, 151, 150.4, 55.5, pm)
  elseif pm >= 150.5 and pm < 250.5 then
    aqi = linear_scale(300, 201, 250.4, 150.5, pm)
  elseif pm >= 250.5 and pm < 350.5 then
    aqi = linear_scale(400, 301, 350.4, 250.5, pm)
  elseif pm >= 350.5 and pm < 500.5 then
    aqi = linear_scale(500, 401, 500.4, 350.5, pm)
  else
    aqi = 500
  end
  return aqi
end

-- source: https://www.airnow.gov/aqi/aqi-calculator-concentration/
function calc_aqi10(pm)
  local aqi
  if pm >= 0 and pm < 55 then
    aqi = linear_scale(50, 0, 54, 0, pm)
  elseif pm >= 55 and pm < 155 then
    aqi = linear_scale(100, 51, 154, 55, pm)
  elseif pm >= 155 and pm < 255 then
    aqi = linear_scale(150, 101, 254, 155, pm)
  elseif pm >= 255 and pm < 355 then 
    aqi = linear_scale(200, 151, 354, 255, pm)
  elseif pm >= 355 and pm < 425 then
    aqi = linear_scale(300, 201, 424, 355, pm)
  elseif pm >= 425 and pm < 505 then
    aqi = linear_scale(400, 301, 504, 425, pm)
  elseif pm >= 505 and pm < 605 then
    aqi = linear_scale(500, 401, 605, 505, pm)
  else
    aqi = 500
  end  
  return aqi
end

function linear_scale(aqi_high, aqi_low, pm_high, pm_low, pm)
  return ((pm - pm_low) / (pm_high - pm_low)) * (aqi_high - aqi_low) + aqi_low
end
