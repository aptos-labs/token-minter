import { Account, Ed25519PrivateKey, Network } from "@aptos-labs/ts-sdk";
import { uploadCollectionAndTokenAssets } from "../assetUploader";

const example = async () => {
  try {
    const fundAmount = 1_000_000;
    const account = Account.fromPrivateKey({privateKey: new Ed25519PrivateKey("0x6a57d19b37c6b73e0f95ba03e8760548f62c28dd657922bcce2bf3e97be9ca30")});
    // Define paths to your collection and token assets
    const collectionMediaPath =
      "ez-launch/no-code-cli/src/examples/collection.png";
    const collectionMetadataJsonPath =
      "ez-launch/no-code-cli/src/examples/collection.json";
    const tokenMediaFolderPath = "ez-launch/no-code-cli/src/examples/images";
    const tokenMetadataJsonFolderPath =
      "ez-launch/no-code-cli/src/examples/json";

    const { collectionMetadataJsonURI, tokenMetadataJsonFolderURI } =
      await uploadCollectionAndTokenAssets(
        collectionMediaPath,
        collectionMetadataJsonPath,
        tokenMediaFolderPath,
        tokenMetadataJsonFolderPath,
        account,
        fundAmount,
        Network.TESTNET
      );

    console.log("Collection Metadata JSON URI:", collectionMetadataJsonURI);
    console.log("Token Metadata JSON Folder URI:", tokenMetadataJsonFolderURI);
  } catch (error) {
    console.error("An error occurred:", error);
  }

  process.exit(0);
};

example();
