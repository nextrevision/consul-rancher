FROM gliderlabs/consul-server:0.6

ENTRYPOINT ["/consul_startup.sh"]

VOLUME ["/data"]

RUN apk --update add curl ca-certificates && \
    curl -Ls -o /bin/giddyup https://github.com/cloudnautique/giddyup/releases/download/v0.7.0/giddyup && \
    rm -rf /var/cache/apk/*

RUN curl -o ui.zip https://releases.hashicorp.com/consul/0.6.3/consul_0.6.3_web_ui.zip && \
    mkdir ui && \
    unzip -d ui ui.zip && \
    rm ui.zip

ADD files/consul_startup.sh /consul_startup.sh

RUN chmod +x /consul_startup.sh /bin/giddyup
