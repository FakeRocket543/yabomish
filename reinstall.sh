 cd /Users/fl/Python/yabomish
 rm -rf YabomishIM/build
 killall YabomishIM
 killall YabomishIM 2>/dev/null; sleep 1
 bash YabomishPrefs/build_prefs.sh
 cp -R YabomishPrefs/YabomishPrefs.app /Applications/
 sh setup.sh
