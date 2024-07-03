# This script creates/updates credentials.json file which is used
# to authorize publisher when publishing packages to pub.dev

# Checking whether the secrets are available as environment
# variables or not.
if [ -z "${PUB_ACCESS_TOKEN}" ]; then
  echo "Missing PUB_ACCESS_TOKEN environment variable"
  exit 1
fi

if [ -z "${PUB_REFRESH_TOKEN}" ]; then
  echo "Missing PUB_REFRESH_TOKEN environment variable"
  exit 1
fi

if [ -z "${PUB_TOKEN_ENDPOINT}" ]; then
  echo "Missing PUB_TOKEN_ENDPOINT environment variable"
  exit 1
fi

if [ -z "${PUB_EXPIRATION}" ]; then
  echo "Missing PUB_EXPIRATION environment variable"
  exit 1
fi

# Create credentials.json file.
mkdir -p  $HOME/.config/dart/
cat <<EOF > $HOME/.config/dart/pub-credentials.json
{
  "accessToken":"${PUB_ACCESS_TOKEN}",
  "refreshToken":"${PUB_REFRESH_TOKEN}",
  "tokenEndpoint":"${PUB_TOKEN_ENDPOINT}",
  "scopes":["https://www.googleapis.com/auth/userinfo.email","openid"],
  "expiration":${PUB_EXPIRATION}
}
EOF