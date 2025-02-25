# README の概要
本プロジェクトは、ローカル環境にCorda5の開発用クラスタを迅速に構築するための資材および手順をまとめたものである。

Corda5の概要についてはドキュメントを参照(https://docs.r3.com/en/platform/corda/5.2.html)

# 前提条件
- OS: Ubuntu 22.04
- Java: Zulu Java 17 (https://www.azul.com/downloads/?version=java-17-lts&package=jdk#zulu)
- K3s: 1.31.5+k3s1 (https://k3s.io/)
- helm: v3.17.0 (https://github.com/helm/helm/releases)
- Corda CLI v5.2.0 (https://docs.r3.com/en/platform/corda/5.2/developing-applications/tooling/installing-corda-cli.html)
- VsCode v1.97.2 もしくはIntellij v2021.x.x(xは任意) Community Edition

# 手順
## ネットワークの種類
本章では、「独自作成のスクリプトを使用して動的ネットワークを構成する」手順、「Cordaが用意した開発ツールであるCordapp Template Javaを使用して静的ネットワークを構成する」手順それぞれについて記述する。
静的ネットワークは「事前に参加者をファイルに定義したネットワーク」、動的ネットワークは「Membership Group Manager(MGM)が同的にネットワーク参加者の参加・離脱等を調整するネットワーク」を指す。
## 動的ネットワーク構築手順
1. k3sクラスタにcorda-dev-prereqsチャートをデプロイする。corda-dev-prereqsは、Corda5クラスタに必要なPostgreSQL、Kafkaのpodを構築する。
helm install prereqs -n corda corda-dev-prereqs/charts/corda-dev-prereqs --timeout 10m  --debug --create-namespace
2. k3sクラスタにCordaをデプロイする。
helm install corda -n corda corda --values corda/values-prereqs.yaml --debug
3. ポートフォワードを設定し、REAT API経由でCordaを操作できるようにする
kubectl port-forward --namespace corda deployment/corda-rest-worker 8888
4. Cordaクラスタの起動確認を行う。以下のcurlコマンドを実行し、レスポンスが返ってくれば正常に起動している。
リクエスト
curl -k -u admin:admin https://127.0.0.1:8888/api/v5_2/cpi
レスポンス
{"cpis":[]}
5. mgmディレクトリで新規ターミナルを起動する
6. mgm-setup.shを実行し、CordaクラスタにMGMを構築する。以下のメッセージが表示されれば完了とする。
./mgm-setup.sh

メッセージ
registration status: APPROVED
MGM setup finished
7. notaryディレクトリで新規ターミナルを起動する

8. notary-setup.shを実行し、Cordaクラスタにnotaryを構築する。以下のメッセージが表示されれば完了とする。
./notary-setup.sh

メッセージ
registration status: APPROVED
notary setup finished

9. memberディレクトリで新規ターミナルを起動する

10. notary-setup.shを実行し、Cordaクラスタにmemberを構築する。以下のメッセージが表示されれば完了とする。
./notary-setup.sh {仮想ノード名} {CPIチェックサム}
(CPIチェックサムは、既にほかのメンバーを追加済みの時など、Cordaクラスタにデプロイ済みのCPIがあり、それと紐づけたメンバー仮想ノードを作成したい場合に入力する。空の場合は新規にCPIを作成、デプロイする)

例: ./notary-setup.sh Alice

メッセージ
registration status: APPROVED
member setup finished
11. 以下のcurlコマンドを実行し、レスポンスにMGM(1台)、notary(１台)、メンバー(作成した数)の仮想ノードが含まれていれば完了とする。

curl -k -u admin:admin https://127.0.0.1:8888/api/v5_2/virtualnode | jq .

レスポンス例
{
  "virtualNodes": [
    {
      "holdingIdentity": {
        "x500Name": "CN=Bob, O=Local, L=London, C=GB",
        "groupId": "33636458-818b-42f5-9380-d180b99c6ea8",
        "shortHash": "11FAB0433C43",
        "fullHash": "11FAB0433C4309037EC70078092560D45728419AEFD7A041F1162204D63F2DF2"
      },
      "cpiIdentifier": {
        "cpiName": "Flow",
        "cpiVersion": "1.0.0.0-SNAPSHOT",
        "signerSummaryHash": "SHA-256:F216E7C27627471724706E44E511E6F2C85799AF1833041EEE3C46091AF667D7"
      },
      "vaultDdlConnectionId": "bc0ae181-c3d7-470d-a780-f38ac2a3f619",
      "vaultDmlConnectionId": "05b2b8dc-ad6f-4f1d-8e34-2766d137a79e",
      "cryptoDdlConnectionId": "968ae040-57a4-4fce-ab29-e2d6a9b62e8a",
      "cryptoDmlConnectionId": "2d7f50ee-fca4-49a0-9b2f-6ad468a02303",
      "uniquenessDdlConnectionId": "eee3c79e-0a39-4cfb-aebd-e24326608931",
      "uniquenessDmlConnectionId": "d9aa1304-dd71-4f60-9991-2e6c5b07a5a8",
      "hsmConnectionId": "null",
      "flowP2pOperationalStatus": "ACTIVE",
      "flowStartOperationalStatus": "ACTIVE",
      "flowOperationalStatus": "ACTIVE",
      "vaultDbOperationalStatus": "ACTIVE",
      "operationInProgress": null,
      "externalMessagingRouteConfiguration": null
    },
    {
      "holdingIdentity": {
        "x500Name": "CN=Alice, O=Local, L=London, C=GB",
        "groupId": "33636458-818b-42f5-9380-d180b99c6ea8",
        "shortHash": "1F4ED6166440",
        "fullHash": "1F4ED61664408636A01C6952A6AA40258DE39F4360052EDFADDD0D0724A575CF"
      },
      "cpiIdentifier": {
        "cpiName": "Flow",
        "cpiVersion": "1.0.0.0-SNAPSHOT",
        "signerSummaryHash": "SHA-256:F216E7C27627471724706E44E511E6F2C85799AF1833041EEE3C46091AF667D7"
      },
      "vaultDdlConnectionId": "b51e8ed5-63b0-4a51-b5f4-370d6223d34c",
      "vaultDmlConnectionId": "632a9a1e-b29c-4785-b1bf-5a010fba1209",
      "cryptoDdlConnectionId": "92355c49-74ff-40b3-9034-123585d5da75",
      "cryptoDmlConnectionId": "fbd18d1b-4f12-47b6-8242-2bd66621f51f",
      "uniquenessDdlConnectionId": "964b7b2c-a71e-499a-b4be-d694d92f9db0",
      "uniquenessDmlConnectionId": "b873d07f-023e-4808-8a48-ed3648f32934",
      "hsmConnectionId": "null",
      "flowP2pOperationalStatus": "ACTIVE",
      "flowStartOperationalStatus": "ACTIVE",
      "flowOperationalStatus": "ACTIVE",
      "vaultDbOperationalStatus": "ACTIVE",
      "operationInProgress": null,
      "externalMessagingRouteConfiguration": null
    },
    {
      "holdingIdentity": {
        "x500Name": "CN=Notary, O=Local, L=London, C=GB",
        "groupId": "33636458-818b-42f5-9380-d180b99c6ea8",
        "shortHash": "41B0A3C5A54E",
        "fullHash": "41B0A3C5A54E0D406E76E76DF0A03651383AE4D2F617A69FA8B0E1235766AF69"
      },
      "cpiIdentifier": {
        "cpiName": "Notary",
        "cpiVersion": "1.0.0.0-SNAPSHOT",
        "signerSummaryHash": "SHA-256:D7AE8419C91809D9FB006EC06ADC289C52BABAE0616E98E706A78B50CCF8CF7D"
      },
      "vaultDdlConnectionId": "20f2c21a-3c6e-4c49-94e0-c91d848683ea",
      "vaultDmlConnectionId": "85aa0bda-462a-410f-9c98-338f9c8f347b",
      "cryptoDdlConnectionId": "ee58ba86-bb81-4957-9dfb-a19c48c9912b",
      "cryptoDmlConnectionId": "bd900628-115c-4283-aacd-77f5e9925edb",
      "uniquenessDdlConnectionId": "e15bef46-fa69-4baf-bdb0-1c55cba37d46",
      "uniquenessDmlConnectionId": "0ec1a8ab-91e7-47be-8ffe-2e584ba8552a",
      "hsmConnectionId": "null",
      "flowP2pOperationalStatus": "ACTIVE",
      "flowStartOperationalStatus": "ACTIVE",
      "flowOperationalStatus": "ACTIVE",
      "vaultDbOperationalStatus": "ACTIVE",
      "operationInProgress": null,
      "externalMessagingRouteConfiguration": null
    },
    {
      "holdingIdentity": {
        "x500Name": "CN=MGM, O=Local, L=London, C=GB",
        "groupId": "33636458-818b-42f5-9380-d180b99c6ea8",
        "shortHash": "81802BFE3BD5",
        "fullHash": "81802BFE3BD5D0EB620E5E076A09F0A02167C781F725BA37FC0804E66F53C670"
      },
      "cpiIdentifier": {
        "cpiName": "MGM",
        "cpiVersion": "1.0.0.0-SNAPSHOT",
        "signerSummaryHash": "SHA-256:1FAF3E5E9AF5D6B823CAA88B938EBDBEE2478F2782943C82ED4EDE8C0D46784B"
      },
      "vaultDdlConnectionId": "665a38fa-9e38-4b1b-88e3-1e741899051d",
      "vaultDmlConnectionId": "93dc2d94-4ea6-49b2-95cf-778c475de32c",
      "cryptoDdlConnectionId": "3bfc24f0-035e-4819-908d-a53d2c88a4fa",
      "cryptoDmlConnectionId": "421ec811-d5e0-4fe3-ab60-b15eeed10a3a",
      "uniquenessDdlConnectionId": "e10fc651-53d9-4ae9-af88-8ad8b1d9096b",
      "uniquenessDmlConnectionId": "473de28a-d716-469e-89b3-d4490518869b",
      "hsmConnectionId": "null",
      "flowP2pOperationalStatus": "ACTIVE",
      "flowStartOperationalStatus": "ACTIVE",
      "flowOperationalStatus": "ACTIVE",
      "vaultDbOperationalStatus": "ACTIVE",
      "operationInProgress": null,
      "externalMessagingRouteConfiguration": null
    }
  ]
}