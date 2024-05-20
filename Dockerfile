# syntax = docker/dockerfile:1.0-experimental
FROM eclipse-temurin:17-jdk-jammy as android-builder

# Install dependencies
RUN apt update && apt install -y curl git unzip xz-utils wget
#env variables used for installations
ENV ANDROID_COMPILE_SDK="33"
ENV ANDROID_BUILD_TOOLS="33.0.0"
ENV ANDROID_SDK_TOOLS="11076708_latest"
ENV ANDROID_HOME_PATH="/usr/local/Android/sdk"

ENV FLUTTER_HOME=/usr/local/flutter
ENV PATH=$FLUTTER_HOME/bin:$PATH

# Prepare Android directories and system variables
RUN mkdir -p .android && touch .android/repositories.cfg

# Download and extract Android SDK command-line tools
RUN wget -O /tmp/android-sdkmanager.zip https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS}.zip
RUN mkdir -p dest
RUN mkdir -p ${ANDROID_HOME_PATH}
RUN unzip -q /tmp/android-sdkmanager.zip -d ${ANDROID_HOME_PATH} && rm /tmp/android-sdkmanager.zip

# Set environment variables directly
ENV ANDROID_HOME=${ANDROID_HOME_PATH}
ENV ANDROID_SDK_ROOT=${ANDROID_HOME_PATH}
ENV PATH=${ANDROID_HOME_PATH}/cmdline-tools/bin:${ANDROID_HOME_PATH}/platform-tools:${ANDROID_HOME_PATH}/platforms:/flutter/bin:$PATH

RUN yes | ${ANDROID_HOME}/cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_HOME} --licenses
# Update Android SDK
RUN ${ANDROID_HOME}/cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_HOME} --update
# Install necessary Android SDK components
RUN ${ANDROID_HOME}/cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_HOME} "build-tools;${ANDROID_BUILD_TOOLS}" "platform-tools" "platforms;android-${ANDROID_COMPILE_SDK}" "sources;android-${ANDROID_COMPILE_SDK}"

#Clone project to app structure
RUN git clone https://github.com/karemSD/Mimal-Shop-app.git /app
RUN git clone https://github.com/flutter/flutter.git $FLUTTER_HOME

# Run Flutter doctor to check for any issues
RUN flutter doctor

# Continue with the rest of your Dockerfile steps
WORKDIR /app
RUN flutter pub get
# Build APK release
RUN flutter build apk --release --no-tree-shake-icons

# Copy GitHub secrets to temporary files to deploy apk to github repo
RUN --mount=type=secret,id=github_username cat /run/secrets/github_username > /tmp/github_username
RUN --mount=type=secret,id=github_token cat /run/secrets/github_token > /tmp/github_token
RUN --mount=type=secret,id=github_email cat /run/secrets/github_email > /tmp/github_email
RUN --mount=type=secret,id=github_repository cat /run/secrets/github_repository > /tmp/github_repository
# Configure global git user email and name
RUN git config --global user.email "$(cat /tmp/github_email)"
RUN git config --global user.name "$(cat /tmp/github_username)"

# Create git credentials file with repository URL
RUN echo "https://$(cat /tmp/github_username):$(cat /tmp/github_token)@$(cat /tmp/github_repository)" > /tmp/git-credentials

# Move the APK to a destination folder
RUN mkdir -p /dest
RUN mv "/app/build/app/outputs/flutter-apk/app-release.apk" "/dest/my_app_$(date +'%Y-%m-%d_%H-%M-%S').apk"

# Change working directory to the destination folder
WORKDIR /dest
# Initialize a new Git repository
RUN git init

# Add the remote repository
RUN git remote add origin "$(cat /tmp/github_repository)"
RUN git add .
RUN APK_NAME=$(ls /dest/*.apk | awk -F '/' '{print $NF}' | sed 's/.apk//') && \
    git commit -m "$APK_NAME"
# Check out the main branch
RUN git checkout -b main
# Push changes to the remote repository
RUN git push -u  origin main


#web app build for flutter web build
FROM ubuntu:jammy as web-builder
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    libglu1-mesa \
    fonts-droid-fallback

RUN git clone https://github.com/karemSD/Mimal-Shop-app.git /app

ENV FLUTTER_HOME=/usr/local/flutter
ENV PATH=$FLUTTER_HOME/bin:$PATH

RUN git clone https://github.com/flutter/flutter.git $FLUTTER_HOME
RUN flutter doctor

WORKDIR /app
RUN flutter upgrade
RUN flutter clean
RUN flutter pub get
RUN flutter build web

#using nginx web server
FROM nginx:alpine as web

COPY --from=web-builder /app/build/web/* /usr/share/nginx/html
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
