# # Build the custom Docker image
IMAGE_NAME="awx-ssh-client"
echo "[Clients] Building custom Docker image: ${IMAGE_NAME}"
docker build -t "${IMAGE_NAME}" "$(pwd)"