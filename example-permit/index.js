// Copyright (c) Aptos
// SPDX-License-Identifier: Apache-2.0

const { AptosAccount, HexString, TxnBuilderTypes, BCS } = require("aptos");

class MintPermit {
  constructor(
    contractAddr, //: TxnBuilderTypes.AccountAddress,
    moduleName, //: string,
    structName, //: string,
    name, //: string,
    description, //: string,
    uri, //: string,
    recipientAddr //: TxnBuilderTypes.AccountAddress,
  ) {
    this.contractAddr = contractAddr;
    this.moduleName = moduleName;
    this.structName = structName;
    this.name = name;
    this.description = description;
    this.uri = uri;
    this.recipientAddr = recipientAddr;
  }

  // serializer is BCS.Serializer
  serialize(serializer) {
    this.contractAddr.serialize(serializer);
    serializer.serializeStr(this.moduleName);
    serializer.serializeStr(this.structName);
    serializer.serializeStr(this.name);
    serializer.serializeStr(this.description);
    serializer.serializeStr(this.uri);
    this.recipientAddr.serialize(serializer);
  }
}

// NOTE: Just for example purposes
// public key: 0xe21d1816f2a03acc8786364fee7bab0b23e427f5a5f7f4cf2a8842437416b2dc
const PRIVATE_KEY =
  "0x2cb669a6d827a512db87823b0a584ad3e7a5e7c095fede352f5157916b5ffe87";
const CONTRACT_ADDR =
  "0x405bcb8a1446a9a14f574fef4a99baf2d8db1a81ad0393179ef7bb559c51dda4";
const MINT_TO_ADDR =
  "0xaceef506a10f3ef427d09b2e1410e79bbdcd9b3a0c3165ac2809b514db128d4e";
const signer = new AptosAccount(new HexString(PRIVATE_KEY).toUint8Array());
console.log(signer.pubKey());
const challenge = new MintPermit(
  TxnBuilderTypes.AccountAddress.fromHex(CONTRACT_ADDR),
  "main",
  "MintPermit",
  "Token Name",
  "Token Description",
  "https://aptos.dev/img/aptos_word_dark.svg",
  TxnBuilderTypes.AccountAddress.fromHex(MINT_TO_ADDR)
);
const challengeHex = HexString.fromUint8Array(BCS.bcsToBytes(challenge));
const proof = signer.signHexString(challengeHex);
console.log({
  proof,
});
