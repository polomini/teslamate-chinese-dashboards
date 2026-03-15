# 基于 TeslaMate 官方 Grafana 镜像
FROM teslamate/grafana:latest

# 标签信息
LABEL maintainer="wjsall"
LABEL description="TeslaMate Grafana with Chinese Dashboards"
LABEL version="1.2.0"

# 强制中文语言设置（关键！）
ENV GF_DEFAULT_LANGUAGE=zh-Hans
ENV GF_USERS_DEFAULT_LANGUAGE=zh-Hans
ENV GF_USERS_DEFAULT_LOCALE=zh-Hans

# 复制中文 Dashboard 到 TeslaMate 标准位置
COPY grafana/dashboards/zh-cn/*.json /dashboards/

# 复制 Internal Dashboards
COPY grafana/dashboards/internal/*.json /dashboards/internal/

# 覆盖基础镜像的 datasource.yml，加入显式 uid: TeslaMate
# 避免 Grafana 自动生成随机 UID 导致仪表板无数据
COPY grafana/provisioning/datasources/datasource.yml /etc/grafana/provisioning/datasources/datasource.yml

# 暴露端口
EXPOSE 3000
