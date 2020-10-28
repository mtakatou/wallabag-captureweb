FROM debian:stretch

ENV DEBIAN_FRONTEND noninteractive
RUN apt update && apt upgrade -y

RUN apt install -y --no-install-recommends wget curl unzip ca-certificates bash apt-utils gettext-base
RUN apt install -y build-essential make gcc g++

RUN sh -c 'echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list' && \
	wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && \
	apt-get update && \
	apt-get install -y google-chrome-stable

RUN apt-get install -y unzip && \
	curl -LO https://chromedriver.storage.googleapis.com/2.37/chromedriver_linux64.zip && \
	unzip chromedriver_linux64.zip && \
	mv chromedriver /usr/local/bin/

RUN apt update && apt install -y fonts-ipafont-gothic fonts-ipafont-mincho jpegoptim imagemagick ghostscript
RUN apt update && apt install -y python3 python3-pip
RUN pip3 install pillow selenium

RUN apt update && apt install -y cpanminus libjson-perl libxml-simple-perl libssl-dev liblwp-protocol-https-perl
RUN cpanm -n File::Slurp LWP::UserAgent Time::Progress Try::Tiny

RUN apt update && apt install -y patch

RUN apt remove -y build-essential make gcc g++
RUN apt-mark manual $(apt --dry-run autoremove | grep -Po '^Remv \K[^ ]+' | grep ^lib | grep -v -e dev$ -e ^libx -e doc$ )
RUN apt autoremove -y
RUN apt clean

COPY policy.xml /etc/ImageMagick-6/policy.xml
COPY docker_capture_web/screenshot.py /
COPY sc.diff /
RUN patch -p1 < /sc.diff
COPY addimage.pl /

CMD ["/addimage.pl"]
