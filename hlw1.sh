#!/usr/bin/bash
#!/bin/bash
docker run -d --name emby2 -v /etc/nsswitch.conf:/etc/nsswitch.conf -v /mnt/media_rw/d48ded09-158b-4536-b78b-0279c6936327/.ugreen_nas/312373/Docker/xiaoyadata/config:/config -v /mnt/media_rw/d48ded09-158b-4536-b78b-0279c6936327/.ugreen_nas/312373/Docker/xiaoyadata/xiaoya:/media --user 0:0 --net=host --add-host="xiaoya.host:192.168.0.105" --restart always emby/embyserver:4.8.0.56