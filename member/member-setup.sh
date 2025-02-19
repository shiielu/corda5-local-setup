#!/bin/bash -e
echo "member setup start"


RPC_HOST=localhost
RPC_PORT=8888
P2P_GATEWAY_HOST=corda-p2p-gateway-worker.corda
P2P_GATEWAY_PORT=8080

REST_API_URL="https://$RPC_HOST:$RPC_PORT/api/v5_2"

REST_API_USER="admin"
REST_API_PASSWORD="admin"

WORK_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")

KEY_STORE="signingkeys.pfx"
STORE_PASS="keystore password"
KEY_ALIAS="signing key 1"
CPB_ALIAS="Member cpb cert"

MEMBER_CPI_FILE="Member-1.0.0.0-SNAPSHOT.cpi"
CPB_CERT="member-cpb-cert.pem"
CPI_CERT="member-cpi-cert.pem"
SAMPLE_FLOW_CPB_FILE="workflows-1.0-SNAPSHOT-package.cpb"
SAMPLE_CONTRACT_CPB_FILE="contracts-1.0-SNAPSHOT-package.cpb"
SIGNED_MEMBER_CPB_FILE="signed-workflows-1.0-SNAPSHOT-package.cpb"
RUNTIME_OS_PATH="/home/shiielu/corda5-2-local/corda-runtime-os"
CERTIFICATE_REQUEST_PATH="request.csr"
CERTIFICATE_PATH="/tmp/ca/request/certificate.pem"
GROUP_POLICY="GroupPolicy.json"
CORDA_DEFAULT_CERT="gradle-plugin-default-key.pem"
CORDA_DEFAULT_KEY_ALIAS="gradle plugin default key"

MGM_VNODE_X500_NAME="CN=MGM, O=Local, L=London, C=GB"
MEMBER_NAME=$1
MEMBER_VNODE_X500NAME="CN=$MEMBER_NAME, O=Local, L=London, C=GB"

if [ "$#" -eq 0 ]; then
    echo -e "Error: メンバー名を引数として渡してください\n例:   ./member-setup.sh Alice"

    exit 1
fi


# グループポリシー作成
if [[ -e "$WORK_DIR/$GROUP_POLICY" ]]; then
    rm  "$WORK_DIR/$GROUP_POLICY"
    echo "group policy regenerate"
fi
# MGM仮想ノードのIDを取得
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -X GET $REST_API_URL/virtualnode)
echo "$RESPONSE" | jq .
MGM_HOLDING_ID=$(echo "$RESPONSE" | jq -r --arg xname "$MGM_VNODE_X500_NAME"  '.virtualNodes[] | select(.holdingIdentity.x500Name == $xname) | .holdingIdentity.shortHash')
sleep 5
# グループポリシーファイルをMGMからエクスポート
curl -k -u $REST_API_USER:$REST_API_PASSWORD -X GET $REST_API_URL/mgm/$MGM_HOLDING_ID/info | jq . > "$WORK_DIR/$GROUP_POLICY"






if [[ -e "$WORK_DIR/$KEY_STORE" ]]; then
    rm  "$WORK_DIR/$KEY_STORE"
    echo "key store regenerate"
fi
# Member CPI署名鍵作成
keytool -genkeypair -alias "$KEY_ALIAS" -keystore "$KEY_STORE" -storepass "$STORE_PASS" -dname "$MEMBER_VNODE_X500NAME" -keyalg RSA -storetype pkcs12 -validity 4000


# CPB証明書をインポート

keytool -importcert -keystore "$KEY_STORE" -storepass "$STORE_PASS" -noprompt -alias "r3-ca-key" -file "r3-ca-key.pem"
keytool -importcert -keystore signingkeys.pfx -storepass "keystore password" -noprompt -alias gradle-plugin-default-key -file gradle-plugin-default-key.pem
sleep 1
# Member FLOW CPI作成
if [[ -e "$WORK_DIR/$MEMBER_CPI_FILE" ]]; then
    rm "$WORK_DIR/$MEMBER_CPI_FILE"
    echo "cpi file regenerate"
fi
corda-cli.sh package create-cpi \
--group-policy "$WORK_DIR/GroupPolicy.json" \
--cpb "$WORK_DIR/$SAMPLE_FLOW_CPB_FILE" \
--cpi-name "Member" \
--cpi-version "1.0.0.0-SNAPSHOT" \
--file "$WORK_DIR/$MEMBER_CPI_FILE" \
--keystore "$WORK_DIR/$KEY_STORE" \
--storepass "$STORE_PASS" \
--key "$KEY_ALIAS"
echo "flow cpi created"
sleep 1





# 署名検証用の証明書作成
if [[ -e "$WORK_DIR/$CPI_CERT" ]]; then
    rm  "$WORK_DIR/$CPI_CERT"
    echo "cpi singed cert regenerate"
fi
keytool -exportcert -rfc -alias "$KEY_ALIAS" -keystore "$KEY_STORE" -storepass "$STORE_PASS" -file "$CPI_CERT"
echo "CPI cert created"

# 証明書をCordaへアップロード
sleep 5
curl -k -u $REST_API_USER:$REST_API_PASSWORD -X PUT -F alias="member-cpi-key-cert" -F certificate=@"$WORK_DIR/$CPI_CERT" $REST_API_URL/certificate/cluster/code-signer
sleep 1
curl -k -u $REST_API_USER:$REST_API_PASSWORD -X PUT -F alias="gradle-plugin-default-key" -F certificate=@"$WORK_DIR/$CORDA_DEFAULT_CERT" $REST_API_URL/certificate/cluster/code-signer
sleep 1
curl -k -u $REST_API_USER:$REST_API_PASSWORD -X PUT -F alias="r3-ca-key" -F certificate=@"$WORK_DIR/r3-ca-key.pem" $REST_API_URL/certificate/cluster/code-signer

echo "CPI cert uploaded to corda"

# CPIをCordaへアップロード
sleep 5
RESPONSE=$(curl -k -u "$REST_API_USER:$REST_API_PASSWORD" -F upload=@$WORK_DIR/$MEMBER_CPI_FILE $REST_API_URL/cpi/)
echo "$RESPONSE" | jq .
echo "CPI uploaded to corda"
CPI_ID=$(echo "$RESPONSE" | jq -r '.id')

# CPIチェックサム取得
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD $REST_API_URL/cpi/status/$CPI_ID)
echo "$RESPONSE" | jq .
CPI_CHECKSUM=$(echo "$RESPONSE" | jq -r '.cpiFileChecksum')

# member仮想ノード作成
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -d "{\"request\": {\"cpiFileChecksum\": \"$CPI_CHECKSUM\", \"x500Name\": \"$MEMBER_VNODE_X500NAME\"}}" $REST_API_URL/virtualnode)
echo "$RESPONSE" | jq .
echo "Member VNode created"


REQUEST_ID=$(echo "$RESPONSE" | jq -r '.requestId')
echo "request ID: $REQUEST_ID"

sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -X GET $REST_API_URL/virtualnode/status/$REQUEST_ID)
echo "$RESPONSE" | jq .
MEMBER_HOLDING_ID=$(echo "$RESPONSE" | jq -r '.resourceId')
echo "Member holding ID: $MEMBER_HOLDING_ID"

# セッション開始キー(MGMとのTLS通信用)の作成
curl -k -u $REST_API_USER:$REST_API_PASSWORD -X POST $REST_API_URL/hsm/soft/$MEMBER_HOLDING_ID/SESSION_INIT
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -X POST $REST_API_URL/key/$MEMBER_HOLDING_ID/alias/$MEMBER_HOLDING_ID-session/category/SESSION_INIT/scheme/CORDA.ECDSA.SECP256R1)
echo "$RESPONSE" | jq .
SESSION_KEY_ID=$(echo "$RESPONSE" | jq -r '.id')

echo "HSM and session key created"
echo "sessison key: $SESSION_KEY_ID"

# 台帳キーの作成
curl -k -u $REST_API_USER:$REST_API_PASSWORD -X POST $REST_API_URL/hsm/soft/$MEMBER_HOLDING_ID/LEDGER
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -X POST $REST_API_URL/key/$MEMBER_HOLDING_ID/alias/$MEMBER_HOLDING_ID-ledger/category/LEDGER/scheme/CORDA.ECDSA.SECP256R1)
echo "$RESPONSE" | jq .
LEDGER_KEY_ID=$(echo "$RESPONSE" | jq -r '.id')

echo "HSM and session key created"
echo "sessison key: $LEDGER_KEY_ID"

# memberの通信プロパティ編集
sleep 5
curl -i -k -u $REST_API_USER:$REST_API_PASSWORD -X PUT -d '{"p2pTlsCertificateChainAlias": "p2p-tls-cert", "useClusterLevelTlsCertificateAndKey": true, "sessionKeysAndCertificates": [{"sessionKeyId": "'$SESSION_KEY_ID'", "preferred": true}]}' $REST_API_URL/network/setup/$MEMBER_HOLDING_ID
echo " member communication property configured"


# ビルド登録コンテキストの作成


REGISTRATION_CONTEXT='{
  "corda.session.keys.0.id": "'$SESSION_KEY_ID'",
  "corda.session.keys.0.signature.spec": "SHA256withECDSA",
  "corda.ledger.keys.0.id": "'$LEDGER_KEY_ID'",
  "corda.ledger.keys.0.signature.spec": "SHA256withECDSA",
  "corda.endpoints.0.connectionURL": "https://'$P2P_GATEWAY_HOST':'$P2P_GATEWAY_PORT'",
  "corda.endpoints.0.protocolVersion": "1"
}'

# memberのネットワークへの登録
REGISTRATION_REQUEST='{"memberRegistrationRequest":{"context": '$REGISTRATION_CONTEXT'}}'
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD -d "$REGISTRATION_REQUEST" $REST_API_URL/membership/$MEMBER_HOLDING_ID)
echo "$RESPONSE" | jq .

# ネットワーク登録状況確認
REGISTRATION_ID=$(echo "$RESPONSE" | jq -r '.registrationId')
sleep 5
RESPONSE=$(curl -k -u $REST_API_USER:$REST_API_PASSWORD $REST_API_URL/membership/$MEMBER_HOLDING_ID/$REGISTRATION_ID)
echo "$RESPONSE" | jq .
echo "member setup finished"
