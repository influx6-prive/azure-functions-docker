# Build the runtime from source
ARG HOST_VERSION=3.0.15584
FROM mcr.microsoft.com/dotnet/core/sdk:3.1 AS runtime-image
ARG HOST_VERSION

ENV PublishWithAspNetCoreTargetManifest=false

RUN BUILD_NUMBER=$(echo ${HOST_VERSION} | cut -d'.' -f 3) && \
    git clone --branch v${HOST_VERSION} https://github.com/Azure/azure-functions-host /src/azure-functions-host && \
    cd /src/azure-functions-host && \
    HOST_COMMIT=$(git rev-list -1 HEAD) && \
    dotnet publish -v q /p:BuildNumber=$BUILD_NUMBER /p:CommitHash=$HOST_COMMIT src/WebJobs.Script.WebHost/WebJobs.Script.WebHost.csproj -c Release --output /azure-functions-host --runtime linux-x64 && \
    mv /azure-functions-host/workers /workers && mkdir /azure-functions-host/workers && \
    rm -rf /root/.local /root/.nuget /src

RUN EXTENSION_BUNDLE_VERSION=1.6.0 && \
    EXTENSION_BUNDLE_FILENAME=Microsoft.Azure.Functions.ExtensionBundle.1.6.0_linux-x64.zip && \
    apt-get update && \
    apt-get install -y gnupg wget unzip && \
    wget https://functionscdn.azureedge.net/public/ExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle/$EXTENSION_BUNDLE_VERSION/$EXTENSION_BUNDLE_FILENAME && \
    mkdir -p /FuncExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle/$EXTENSION_BUNDLE_VERSION && \
    unzip /$EXTENSION_BUNDLE_FILENAME -d /FuncExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle/$EXTENSION_BUNDLE_VERSION && \
    rm -f /$EXTENSION_BUNDLE_FILENAME && \
    EXTENSION_BUNDLE_VERSION_V2=2.4.0 && \
    EXTENSION_BUNDLE_FILENAME_V2=Microsoft.Azure.Functions.ExtensionBundle.${EXTENSION_BUNDLE_VERSION_V2}_linux-x64.zip && \
    wget https://functionscdn.azureedge.net/public/ExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle/$EXTENSION_BUNDLE_VERSION_V2/$EXTENSION_BUNDLE_FILENAME_V2 && \
    mkdir -p /FuncExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle/$EXTENSION_BUNDLE_VERSION_V2 && \
    unzip /$EXTENSION_BUNDLE_FILENAME_V2 -d /FuncExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle/$EXTENSION_BUNDLE_VERSION_V2 && \
    rm -f /$EXTENSION_BUNDLE_FILENAME_V2 &&\
    find /FuncExtensionBundles/ -type f -exec chmod 644 {} \;

FROM python:3.7-slim-buster
ARG HOST_VERSION

ENV LANG=C.UTF-8 \
    ACCEPT_EULA=Y \
    AzureWebJobsScriptRoot=/home/site/wwwroot \
    HOME=/home \
    FUNCTIONS_WORKER_RUNTIME=python \
    ASPNETCORE_URLS=http://+:80 \
    DOTNET_RUNNING_IN_CONTAINER=true \
    DOTNET_USE_POLLING_FILE_WATCHER=true \
    HOST_VERSION=${HOST_VERSION}

# Install Python dependencies
RUN apt-get update && \
    apt-get install -y wget && \
    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
    apt-get update && \
    apt-get install -y apt-transport-https curl gnupg && \
    curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    curl https://packages.microsoft.com/config/debian/9/prod.list > /etc/apt/sources.list.d/mssql-release.list && \
    # Needed for libss1.0.0 and in turn MS SQL
    echo 'deb http://security.debian.org/debian-security jessie/updates main' >> /etc/apt/sources.list && \
    # install necessary locales for MS SQL
    apt-get update && apt-get install -y locales && \
    echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && \
    locale-gen && \
    # install MS SQL related packages
    apt-get update && \
    apt-get install -y unixodbc msodbcsql17 mssql-tools && \
    # .NET Core dependencies
    apt-get install -y --no-install-recommends ca-certificates \
    libc6 libgcc1 libgssapi-krb5-2 libicu63 libssl1.1 libstdc++6 zlib1g && \
    rm -rf /var/lib/apt/lists/* && \
    # Custom dependencies:
    #  OpenCV dependencies:
    apt-get update && \
    apt-get install -y libglib2.0-0 libsm6 libxext6 libxrender-dev && \
    #  binutils
    apt-get install -y binutils && \
    #  OpenMP dependencies
    apt-get install -y libgomp1 && \
    # mysql dependencies
    apt-get install -y default-libmysqlclient-dev

# Chrome headless dependencies
# https://github.com/puppeteer/puppeteer/blob/main/docs/troubleshooting.md#chrome-headless-doesnt-launch-on-unix
RUN apt-get install -y xvfb gconf-service libasound2 libatk1.0-0 libc6 libcairo2 libcups2 \
    libdbus-1-3 libexpat1 libfontconfig1 libgbm1 libgcc1 libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 \
    libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 \
    libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 \
    libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils wget

COPY --from=runtime-image ["/azure-functions-host", "/azure-functions-host"]
COPY --from=runtime-image [ "/workers/python", "/azure-functions-host/workers/python" ]
COPY --from=runtime-image [ "/FuncExtensionBundles", "/FuncExtensionBundles" ]

ENV FUNCTIONS_WORKER_RUNTIME_VERSION=3.7

CMD [ "/azure-functions-host/Microsoft.Azure.WebJobs.Script.WebHost" ]
