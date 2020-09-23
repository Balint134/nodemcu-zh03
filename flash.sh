#!/bin/sh
DIR=$(pwd)
TOOLS_DIR="$DIR/.tools"

DEFAULT_BAUD=115200
ESPTOOL="$TOOLS_DIR/esptool.py"
LUATOOL="$TOOLS_DIR/luatool.py"

if [ ! -f "$DIR/config.lua" ]; then
  echo "***No 'config.lua' found, use 'config.sample.lua' to create your configuration***"
  exit 1
fi

echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!!!!This script needs sudo access to erase and flash the contents of the NodeMCU device!!!!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
for arg in "$@"; do
  case $arg in
    -p=*|--port=*)
      PORT="${arg#*=}"
      shift
    ;;

    -b=*|--baud=*)
      BAUD="${arg#*=}"
      shift
    ;;

    --remove-tools)
      REMOVE_TOOLS="${arg#*=}"
      shift
    ;;
  esac
done
BAUD=${BAUD:-$DEFAULT_BAUD}

if [ ! -d $TOOLS_DIR ]; then
  mkdir $TOOLS_DIR
fi

if [ ! -f "$TOOLS_DIR/luatool.py" ]; then
  (cd $TOOLS_DIR && curl -O https://raw.githubusercontent.com/4refr0nt/luatool/master/luatool/luatool.py)
fi

if [ ! -f "$TOOLS_DIR/esptool.py" ]; then
  (cd $TOOLS_DIR && curl -O https://raw.githubusercontent.com/espressif/esptool/master/esptool.py)
fi

echo "\nFlashing NodeMCU firmware to device, this will erase all content!"
sudo python $ESPTOOL --port $PORT --baud $BAUD erase_flash
sudo python $ESPTOOL --port $PORT --baud $BAUD write_flash 0x00000 $DIR/nodemcu-fw.bin

if [ $? -ne 0 ]; then
  exit
fi

echo "Successfully flased NodeMCU firmware, start uploading LUA code"
ls | grep .lua | grep -v .sample.lua | while read -r f; do
  echo "\n->Upload file ($f)"

  RET=-1
  while [ $RET -ne 0 ]; do
    sudo python $LUATOOL --port $PORT --baud $BAUD --src $DIR/$f --dest $f >/dev/null 2>&1
    RET=$?
    if [ $RET -eq 0 ]; then
      echo "->Done"
    fi
  done
done

if [ ! -z "$REMOVE_TOOLS" ]; then
  echo "Removing .tools directory"
  rm -r -f $TOOLS_DIR
fi
echo "\nAll good, reset the device and enjoy"
