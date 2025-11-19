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
替换`/data/dk8sfws`目录下的ssl公私钥  
修改`nginx.conf`将证书名称替换成自己的（nginx运行在容器内部所以是当前目录下的）  
然后将域名修改成自己的  
如果存在问题进入容器内部查看对应文件是否存在
```
docker exec -it dk8s-fw /bin/sh
```

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
