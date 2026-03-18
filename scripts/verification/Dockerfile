FROM debian:trixie

# Update and install all required packages
RUN apt-get update && apt-get install -y \
    python3-requests \
    python3-debian \
    equivs \
    mmdebstrap \
    sbuild \
    apt-utils \
    wget \
    vim \
    curl \
    gnupg \
    devscripts \
    dpkg-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN echo "root:100000:65536" >> /etc/subuid && \
    echo "root:100000:65536" >> /etc/subgid

COPY verify.py /usr/local/bin/verify.py
RUN chmod +x /usr/local/bin/verify.py

WORKDIR /workspace

ENTRYPOINT ["python3", "/usr/local/bin/verify.py"]