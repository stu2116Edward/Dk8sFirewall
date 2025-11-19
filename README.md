# Dk8sFirewall

本项目是基于OpenResty实现的流控面板  
源项目作者：https://github.com/yinyue123/DK8sDDosFirewall  

## Demo:
<img width="2559" height="636" alt="屏幕截图 2025-11-19 164221" src="https://github.com/user-attachments/assets/35490bff-ad42-4e15-b128-240583b60b59" />  


查看端口占用情况
```
ss -tulnp | grep :80
ss -tulnp | grep :443
```
关闭系统自带的nginx
```
systemctl stop nginx
systemctl disable nginx
```

创建项目目录
```
mkdir -p /data/dk8sfw
cd /data/dk8sfw
```

下载配置文件
```
for f in nginx.conf env.conf cert.crt cert.key protect.lua record.lua stats.lua; do
  curl -L --retry 3 -o "/data/dk8sfw/$f" "https://github.com/stu2116Edward/Dk8sFirewall/raw/main/$f"
done
````

运行项目
```
docker run -d \
--name dk8s-fw \
--restart always \
--user=root \
--network host \
--cap-add=NET_ADMIN \
--cap-add=NET_RAW \
--cap-add=SYS_ADMIN \
-v /data/dk8sfw:/app:rw \
stu2116edwardhu/dk8s-fw
```

访问监控面板：https://example.com/dk8s.stats  
在你的域名后面跟上`dk8s.stats`后缀  

如需自行构建
```
docker build -f Dockerfile . -t dk8s-fw
```
