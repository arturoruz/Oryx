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
        tk-dev \
        uuid-dev \
        #.NET Core related pre-requisites
        libc6 \
        libgcc1 \
        libgssapi-krb5-2 \
        libicu57 \
        liblttng-ust0 \
        libssl1.0.2 \
        libstdc++6 \
        zlib1g \
        libgdiplus \
    && rm -rf /var/lib/apt/lists/* \
# A temporary folder to hold all content temporarily used to build this image.
# This folder is deleted in the final stage of building this image.
    && mkdir -p ${IMAGES_DIR} \
    && mkdir -p ${BUILD_DIR}

ADD build ${BUILD_DIR}
ADD images ${IMAGES_DIR}
# chmod all script files
RUN mkdir -p /opt/oryx \
    && find ${IMAGES_DIRx} ${BUILD_DIR} -type f -iname "*.sh" -exec chmod +x {} \;

# This is the folder containing 'links' to benv and build script generator
#RUN mkdir -p /opt/oryx

# Install Yarn, HUGO
FROM main AS nodetools-install
ARG BUILD_DIR
ARG IMAGES_DIR
RUN set -ex \
 && ${IMAGES_DIR}/build/installHugo.sh \
 && . ${BUILD_DIR}/__nodeVersions.sh \
 && ${IMAGES_DIR}/receiveGpgKeys.sh 6A010C5166006599AA17F08146C2130DFD2497F5 \
 && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
 && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz.asc" \
 && gpg --batch --verify yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
 && mkdir -p /opt/yarn \
 && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/yarn \
 && mv /opt/yarn/yarn-v$YARN_VERSION /opt/yarn/$YARN_VERSION \
 && rm yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
 && . ${BUILD_DIR}/__nodeVersions.sh \
 && ln -s $YARN_VERSION /opt/yarn/stable \
 && ln -s $YARN_VERSION /opt/yarn/latest \
 && ln -s $YARN_VERSION /opt/yarn/$YARN_MINOR_VERSION \
 && ln -s $YARN_MINOR_VERSION /opt/yarn/$YARN_MAJOR_VERSION \
 && mkdir -p /links \
 && cp -s /opt/yarn/stable/bin/yarn /opt/yarn/stable/bin/yarnpkg /links

FROM main AS final
ARG BUILD_DIR
ARG IMAGES_DIR
ARG SDK_STORAGE_ENV_NAME
ARG SDK_STORAGE_BASE_URL_VALUE
WORKDIR /

ENV ORIGINAL_PATH="$PATH"
ENV ORYX_PATHS="/opt/oryx:/opt/yarn/stable/bin:/opt/hugo/lts"
ENV PATH="${ORYX_PATHS}:${ORIGINAL_PATH}"
COPY images/build/benv.sh /opt/oryx/benv
RUN chmod +x /opt/oryx/benv \
 && mkdir -p /usr/local/share/pip-cache/lib \
 && chmod -R 777 /usr/local/share/pip-cache \
    # Grant read-write permissions to the nuget folder so that dotnet restore
    # can write into it.
 && mkdir -p /var/nuget \
    && chmod a+rw /var/nuget

# .NET Core related environment variables
ENV NUGET_XMLDOC_MODE=skip \
	DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
	NUGET_PACKAGES=/var/nuget


# Copy Yarn and Hugo related content
COPY --from=nodetools-install /opt /opt

# Build script generator content. Docker doesn't support variables in --from
# so we are building an extra stage to copy binaries from correct build stage
COPY --from=buildscriptgenerator /opt/buildscriptgen/ /opt/buildscriptgen/
RUN ln -s /opt/buildscriptgen/GenerateBuildScript /opt/oryx/oryx \
    && ${IMAGES_DIR}/build/php/prereqs/installPrereqs.sh \
# NOTE: do not include the following lines in prereq installation script as
# doing so is causing different version of libargon library being installed
# causing php-composer to fail
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        libargon2-0 \
        libonig-dev \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/oryx

# Bake Application Insights key from pipeline variable into final image
ARG AI_KEY
ENV ORYX_AI_INSTRUMENTATION_KEY=${AI_KEY}

ENV ENABLE_DYNAMIC_INSTALL=true
ENV ${SDK_STORAGE_ENV_NAME} ${SDK_STORAGE_BASE_URL_VALUE}

ARG GIT_COMMIT=unspecified
ARG BUILD_NUMBER=unspecified
ARG RELEASE_TAG_NAME=unspecified
LABEL com.microsoft.oryx.git-commit=${GIT_COMMIT}
LABEL com.microsoft.oryx.build-number=${BUILD_NUMBER}
LABEL com.microsoft.oryx.release-tag-name=${RELEASE_TAG_NAME}

ENTRYPOINT [ "benv" ]