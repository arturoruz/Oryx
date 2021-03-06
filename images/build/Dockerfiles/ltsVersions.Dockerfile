# Folders in the image which we use to build this image itself
# These are deleted in the final stage of the build
ARG IMAGES_DIR=/tmp/oryx/images
ARG BUILD_DIR=/tmp/oryx/build
ARG SDK_STORAGE_ENV_NAME
ARG SDK_STORAGE_BASE_URL_VALUE
# Determine where the image is getting built (DevOps agents or local)
ARG AGENTBUILD

FROM githubrunners-buildpackdeps-stretch AS main
ARG BUILD_DIR
ARG IMAGES_DIR

# Configure locale (required for Python)
# NOTE: Do NOT move it from here as it could have global implications
ENV LANG C.UTF-8

# Install basic build tools
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        git \
        make \
        unzip \
        # The tools in this package are used when installing packages for Python
        build-essential \
        # Required for Microsoft SQL Server
        unixodbc-dev \
        # Required for PostgreSQL
        libpq-dev \
        # Required for mysqlclient
        default-libmysqlclient-dev \
        # Required for ts
        moreutils \
        rsync \
        zip \
        libgdiplus \
        # By default pip is not available in the buildpacks image
        python-pip \
        python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN pip install pip --upgrade
RUN pip3 install pip --upgrade

# A temporary folder to hold all content temporarily used to build this image.
# This folder is deleted in the final stage of building this image.
RUN mkdir -p ${IMAGES_DIR}
RUN mkdir -p ${BUILD_DIR}
ADD build ${BUILD_DIR}
ADD images ${IMAGES_DIR}
# chmod all script files
RUN find ${IMAGES_DIR} -type f -iname "*.sh" -exec chmod +x {} \;
RUN find ${BUILD_DIR} -type f -iname "*.sh" -exec chmod +x {} \;

# This is the folder containing 'links' to benv and build script generator
RUN mkdir -p /opt/oryx

# Install .NET Core
FROM main AS dotnet-install
ARG BUILD_DIR
ARG IMAGES_DIR
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        libc6 \
        libgcc1 \
        libgssapi-krb5-2 \
        libicu57 \
        liblttng-ust0 \
        libssl1.0.2 \
        libstdc++6 \
        zlib1g \
    && rm -rf /var/lib/apt/lists/*

ENV DOTNET_RUNNING_IN_CONTAINER=true \
    DOTNET_USE_POLLING_FILE_WATCHER=true \
	NUGET_XMLDOC_MODE=skip \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
	NUGET_PACKAGES=/var/nuget

RUN mkdir /var/nuget

# Check https://www.microsoft.com/net/platform/support-policy for support policy of .NET Core versions
RUN . ${BUILD_DIR}/__dotNetCoreSdkVersions.sh && \
    DOTNET_SDK_VER=$DOT_NET_CORE_21_SDK_VERSION \
    ${IMAGES_DIR}/build/installDotNetCore.sh

RUN . ${BUILD_DIR}/__dotNetCoreSdkVersions.sh && \
    DOTNET_SDK_VER=$DOT_NET_CORE_31_SDK_VERSION \
    ${IMAGES_DIR}/build/installDotNetCore.sh

RUN set -ex \
    rm -rf /tmp/NuGetScratch \
    && find /var/nuget -type d -exec chmod 777 {} \;

RUN set -ex \
 && sdksDir=/opt/dotnet/sdks \
 && cd $sdksDir \
 && ln -s 2.1 2 \
 && ln -s 3.1 3 \
 && ln -s 3 lts

RUN set -ex \
 && dotnetDir=/opt/dotnet \
 && sdksDir=$dotnetDir/sdks \
 && runtimesDir=$dotnetDir/runtimes \
 && mkdir -p $runtimesDir \
 && cd $runtimesDir \
 && . ${BUILD_DIR}/__dotNetCoreSdkVersions.sh \
 && . ${BUILD_DIR}/__dotNetCoreRunTimeVersions.sh \
 && mkdir $NET_CORE_APP_21 \
 && ln -s $NET_CORE_APP_21 2.1 \
 && ln -s 2.1 2 \
 && echo $DOT_NET_CORE_21_SDK_VERSION > $NET_CORE_APP_21/sdkVersion.txt \
 && mkdir $NET_CORE_APP_31 \
 && ln -s $NET_CORE_APP_31 3.1 \
 && ln -s 3.1 3 \
 && echo $DOT_NET_CORE_31_SDK_VERSION > $NET_CORE_APP_31/sdkVersion.txt \
 # LTS sdk <-- LTS runtime's sdk
 && ln -s 3 lts \
 && ltsSdk=$(cat lts/sdkVersion.txt | tr -d '\r') \
 && ln -s $ltsSdk/dotnet /usr/local/bin/dotnet

# Install Node.js, NPM, Yarn
FROM main AS node-install
ARG BUILD_DIR
ARG IMAGES_DIR
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        jq \
    && rm -rf /var/lib/apt/lists/*
RUN ${IMAGES_DIR}/build/installHugo.sh
COPY build/__nodeVersions.sh /tmp/scripts
RUN cd ${IMAGES_DIR} \
 && . ${BUILD_DIR}/__nodeVersions.sh \
 && ./installPlatform.sh nodejs $NODE8_VERSION \
 && ./installPlatform.sh nodejs $NODE10_VERSION \
 && ./installPlatform.sh nodejs $NODE12_VERSION
RUN ${IMAGES_DIR}/build/installNpm.sh
RUN set -ex \
 && . ${BUILD_DIR}/__nodeVersions.sh \
 && ${IMAGES_DIR}/receiveGpgKeys.sh 6A010C5166006599AA17F08146C2130DFD2497F5 \
 && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
 && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz.asc" \
 && gpg --batch --verify yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
 && mkdir -p /opt/yarn \
 && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/yarn \
 && mv /opt/yarn/yarn-v$YARN_VERSION /opt/yarn/$YARN_VERSION \
 && rm yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz

RUN set -ex \
 && . ${BUILD_DIR}/__nodeVersions.sh \
 && ln -s $NODE8_VERSION /opt/nodejs/8 \
 && ln -s $NODE10_VERSION /opt/nodejs/10 \
 && ln -s $NODE12_VERSION /opt/nodejs/12 \
 && ln -s 12 /opt/nodejs/lts
RUN set -ex \
 && ln -s 6.9.0 /opt/npm/6.9 \
 && ln -s 6.9 /opt/npm/6 \
 && ln -s 6 /opt/npm/latest
RUN set -ex \
 && . ${BUILD_DIR}/__nodeVersions.sh \
 && ln -s $YARN_VERSION /opt/yarn/stable \
 && ln -s $YARN_VERSION /opt/yarn/latest \
 && ln -s $YARN_VERSION /opt/yarn/$YARN_MINOR_VERSION \
 && ln -s $YARN_MINOR_VERSION /opt/yarn/$YARN_MAJOR_VERSION
RUN set -ex \
 && mkdir -p /links \
 && cp -s /opt/nodejs/lts/bin/* /links \
 && cp -s /opt/yarn/stable/bin/yarn /opt/yarn/stable/bin/yarnpkg /links

FROM main AS python
ARG BUILD_DIR
ARG IMAGES_DIR
# It's not clear whether these are needed at runtime...
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        tk-dev \
        uuid-dev \
    && rm -rf /var/lib/apt/lists/*
# https://github.com/docker-library/python/issues/147
ENV PYTHONIOENCODING UTF-8
RUN cd ${IMAGES_DIR} \
    && . ${BUILD_DIR}/__pythonVersions.sh \
    && ./installPlatform.sh python $PYTHON37_VERSION \
    && ./installPlatform.sh python $PYTHON38_VERSION
RUN . ${BUILD_DIR}/__pythonVersions.sh && set -ex \
 && [ -d "/opt/python/$PYTHON37_VERSION" ] && echo /opt/python/$PYTHON37_VERSION/lib >> /etc/ld.so.conf.d/python.conf \
 && [ -d "/opt/python/$PYTHON38_VERSION" ] && echo /opt/python/$PYTHON38_VERSION/lib >> /etc/ld.so.conf.d/python.conf \
 && ldconfig
RUN . ${BUILD_DIR}/__pythonVersions.sh && set -ex \
 && ln -s $PYTHON37_VERSION /opt/python/3.7 \
 && ln -s $PYTHON38_VERSION /opt/python/3.8 \
 && ln -s $PYTHON38_VERSION /opt/python/latest \
 && ln -s $PYTHON38_VERSION /opt/python/stable \
 && ln -s 3.8 /opt/python/3

FROM python AS final
ARG BUILD_DIR
ARG IMAGES_DIR
ARG SDK_STORAGE_ENV_NAME
ARG SDK_STORAGE_BASE_URL_VALUE
WORKDIR /

# Install PHP pre-reqs
RUN ${IMAGES_DIR}/build/php/prereqs/installPrereqs.sh
# Copy PHP versions
RUN cd ${IMAGES_DIR} \
    && . ${BUILD_DIR}/__phpVersions.sh \
    && ./installPlatform.sh php $PHP73_VERSION \
    && ./installPlatform.sh php-composer $COMPOSER_VERSION

RUN ln -s /opt/php/7.3 /opt/php/7 \
 && ln -s /opt/php/7 /opt/php/lts \
 && cd /opt/php-composer \
 && ln -sfn 1.9.3 stable
RUN ln -sfn /opt/php-composer/stable/composer.phar /opt/php-composer/composer.phar
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libargon2-0 \
        libonig-dev \
    && rm -rf /var/lib/apt/lists/*
    
ENV ORIGINAL_PATH="$PATH"
ENV ORYX_PATHS="/opt/oryx:/opt/nodejs/lts/bin:/opt/dotnet/sdks/lts:/opt/python/latest/bin:/opt/php/lts/bin:/opt/php-composer:/opt/yarn/stable/bin:/opt/hugo/lts"
ENV PATH="${ORYX_PATHS}:$PATH"
COPY images/build/benv.sh /opt/oryx/benv
RUN chmod +x /opt/oryx/benv
RUN mkdir -p /usr/local/share/pip-cache/lib
RUN chmod -R 777 /usr/local/share/pip-cache

# Copy .NET Core related content
ENV NUGET_XMLDOC_MODE=skip \
	DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
	NUGET_PACKAGES=/var/nuget
COPY --from=dotnet-install /opt/dotnet /opt/dotnet
COPY --from=dotnet-install /var/nuget /var/nuget
# Grant read-write permissions to the nuget folder so that dotnet restore
# can write into it.
RUN chmod a+rw /var/nuget

# Copy NodeJs, NPM and Yarn related content
COPY --from=node-install /opt /opt

# Build script generator content. Docker doesn't support variables in --from
# so we are building an extra stage to copy binaries from correct build stage
COPY --from=buildscriptgenerator /opt/buildscriptgen/ /opt/buildscriptgen/
RUN ln -s /opt/buildscriptgen/GenerateBuildScript /opt/oryx/oryx

RUN rm -rf /tmp/oryx

# Bake Application Insights key from pipeline variable into final image
ARG AI_KEY
ENV ORYX_AI_INSTRUMENTATION_KEY=${AI_KEY}

ARG GIT_COMMIT=unspecified
ARG BUILD_NUMBER=unspecified
ARG RELEASE_TAG_NAME=unspecified
LABEL com.microsoft.oryx.git-commit=${GIT_COMMIT}
LABEL com.microsoft.oryx.build-number=${BUILD_NUMBER}
LABEL com.microsoft.oryx.release-tag-name=${RELEASE_TAG_NAME}

ENV ${SDK_STORAGE_ENV_NAME} ${SDK_STORAGE_BASE_URL_VALUE}

ENTRYPOINT [ "benv" ]
