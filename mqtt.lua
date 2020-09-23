-- Creates a topic name based on the given topic pattern
function mqtt_topic(topic, ...)
  return string.format(config.mqtt_discovery_pre .. '/' .. topic, ...)
end