# Use an image with java 11 installed as the basis
FROM openjdk:11-jdk

# Set the Java path
ENV JAVA_HOME=/usr/local/openjdk-11
ENV PATH="$JAVA_HOME/bin:${PATH}"

# The directory of the Terraform folder that will be built
ARG TERRAFORM_DIR

# Install the neccessary commands
RUN \
    apt-get update -y && \
    apt-get install unzip -y && \
    apt-get install wget -y && \
    apt-get install vim -y && \
    apt-get install curl -y && \
    apt-get install git -y && \
    apt-get install jq -y

# Install kubectl
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl

# Install awscli
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip ./aws

# Install Terraform
RUN wget https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
RUN unzip terraform_1.7.5_linux_amd64.zip
RUN mv terraform /usr/local/bin/

# Install eksctl
RUN curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"
RUN tar -xzf eksctl_Linux_amd64.tar.gz -C /tmp && rm eksctl_Linux_amd64.tar.gz
RUN mv /tmp/eksctl /usr/local/bin

# Copy the Gradle wrapper files (gradlew and gradle wrapper jar) to the container
COPY gradlew .
COPY settings.gradle.kts .
COPY gradlew.bat .
COPY gradle.properties .
COPY gradle/ /gradle/
COPY buildSrc/ /buildSrc/
COPY validator/ /validator/

# Build gradlew here so that the canary doesn't spend time downloading and building the package
RUN ./gradlew

# Set a custom Gradle user home directory
ENV GRADLE_USER_HOME=/.gradle/

# Create the custom Gradle user home directory
RUN mkdir -p $GRADLE_USER_HOME

# Copy the Gradle cache from the default location to the custom location
RUN cp -r ~/.gradle/* $GRADLE_USER_HOME

COPY "$TERRAFORM_DIR" /terraform/
RUN if echo "$TERRAFORM_DIR" | grep -q "k8s"; then \
      terraform -chdir=/terraform/deploy init && terraform -chdir=/terraform/deploy validate ; \
      terraform -chdir=/terraform/cleanup init && terraform -chdir=/terraform/cleanup validate ; \
    else \
      terraform -chdir=/terraform init && terraform -chdir=/terraform validate ; \
    fi


