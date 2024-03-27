import fs from "fs";
import path from "path";
import { program } from "commander";
import { Account } from "@aptos-labs/ts-sdk";
import prompts from "prompts";
import glob from "glob";
import { uploadCollectionAndTokenAssets } from "./assetUploader";
import { createEZLaunchCollection, preMintTokens } from "./contract";
import { OCTAS_PER_APT, OutJson, TokenMetadata, exitWithError, resolvePath, resolveProfile } from "./utils";

program
  .name("nft-ez-launch")
  .description("CLI to manage and ez launch nft collection")
  .option(
      "-v, --verbose",
      "Print more information. This is useful for debugging purpose.",
      false,
    )
  .version("0.0.1");

program
  .command("upload")
  .description("Uploads NFT assets to a decentralized storage solution.")
  .requiredOption("--profile <aptos-cli-profile>", "The profile name of the Aptos CLI.")
  .requiredOption("--asset-path <asset-path>", "The asset path.")
  .requiredOption("--fund-amount <amount>", "The amount of funds to be used.", parseFloat)
  .action(async (options) => {
    const {
      profile,
      assetPath,
      fundAmount
    } = options;
    const collectionMediaPath = `${assetPath}/collection.png`;
    const collectionMetadataJsonPath = `${assetPath}/collection.json`;
    const tokenMediaFolderPath = `${assetPath}/images`;
    const tokenMetadataJsonFolderPath =  `${assetPath}/json`;

    const [account, network] = await resolveProfile(profile);

    const { collectionMetadataJsonURI, tokenMetadataJsonFolderURI } = await uploadCollectionAndTokenAssets(
      collectionMediaPath,
      collectionMetadataJsonPath,
      tokenMediaFolderPath,
      tokenMetadataJsonFolderPath,
      account,
      fundAmount * OCTAS_PER_APT,
      network,
    );

    console.log("Collection Metadata JSON URI:", collectionMetadataJsonURI);
    console.log("Token Metadata JSON Folder URI:", tokenMetadataJsonFolderURI);
  });

  program
  .command("create-collection")
  .description("Create a NFT collection with pre minted tokens.")
  .requiredOption("--profile <profile>", "The profile name of the Aptos CLI.")
  .requiredOption("--name <name>", "Name of the NFT project.")
  .requiredOption("--asset-path <asset-path>", "The asset path.")
  .action(async (options) => {
    const {
      profile,
      name,
      assetPath,
    } = options;

    try {
      const [account, network] = await resolveProfile(profile);
      console.log(`Profile ${profile} resolved for network ${network} with account address ${account.accountAddress}.`);

      await createCollection(account, name, assetPath);
    } catch (error) {
      console.error(`Error initializing: ${error}`);
    }
  });

program
  .command("validate")
  .description("Validates the NFT collection configuration.")
  .option("--project-path <project-path>", "Path to the NFT project directory.", ".")
  .action(async (options) => {
    const { projectPath } = options;
    await validateProjectConfig(projectPath);
  });

  program
  .command("claim-token")
  .description("Claim Tokens from an EZ Launch Collection.")
  .requiredOption("--profile <profile>", "The profile name of the Aptos CLI.")
  .requiredOption("--ez-launch-config-address <ez-launch-config-address>", "EZLaunchConfig address", ".")
  .action(async (options) => {
    const { profile, ezLaunchConfigAddress } = options;
    
    // TODO(jill) add token claim 

  });

async function validateProjectConfig(projectPath: string) {
    const rawdata = fs.readFileSync(projectPath, 'utf8');
    const config: OutJson =  JSON.parse(rawdata);

    const errors: string[] = [];
    const warnings: string[] = [];

    // Validate collection
    if (!config.collection.name) {
        errors.push("Collection name cannot be empty.");
    }

    if (!config.collection.uri) {
        errors.push("Collection URI cannot be empty.");
    }

    // Validate tokens
    if (config.tokens.length === 0) {
        errors.push("No tokens provided.");
    } else {
      config.tokens.forEach((token, index) => {
          if (!token.name) {
              errors.push(`Token at index ${index} has no name.`);
          }
          if (!token.description) {
              errors.push(`Token at index ${index} has no description.`);
          }
          if (!token.uri) {
              errors.push(`Token at index ${index} has no URI.`);
          }
      });
    }

    if (errors.length > 0) {
        console.error("Errors found in config:");
        errors.forEach((error) => console.error(error));
    }
    
    if (warnings.length > 0) {
        console.warn("Warnings found in config:");
        warnings.forEach((warning) => console.warn(warning));
    }
    
    if (errors.length === 0 && warnings.length === 0) {
        console.log("No issues found in config.");
    }
}

  /**
   * 
   * /assets
       /images
           1.png
           2.png
           3.png
       /json
           1.json
           2.json
           3.json
        / collection.json
        / collection.png
   */
async function createCollection(account: Account, name: string, assetPath: string) {
  const fullPath = resolvePath(".", name);
  if (fs.existsSync(fullPath)) {
      exitWithError(`${fullPath} already exists.`);
  }
  fs.mkdirSync(fullPath, { recursive: true });

  const configPath = path.join(fullPath, "config.json");
  if (fs.existsSync(configPath)) {
      exitWithError(`${configPath} already exists.`);
  }

  // Load the collection metadata from the provided URI
  const collectionMetadataPath = path.join(assetPath, "collection.json");
  const collectionMetadata = JSON.parse(fs.readFileSync(collectionMetadataPath, "utf8"));

  const questions = [
      { type: "confirm", name: "mutableCollectionMetadata", message: "Is collection metadata mutable?", default: false },
      { type: "confirm", name: "mutableTokenMetadata", message: "Is token metadata mutable?", default: false },
      { type: "confirm", name: "randomMint", message: "Enable random mint?", default: false },
      { type: "confirm", name: "isSoulbound", message: "Is the collection soulbound?", default: false },
      { type: "confirm", name: "tokensBurnableByCollectionOwner", message: "Can tokens be burned by the collection owner?", default: false },
      { type: "confirm", name: "tokensTransferrableByCollectionOwner", message: "Can tokens be transferred by the collection owner?", default: false },
      { type: "number", name: "maxSupply", message: "Enter the maximum supply (0 for no limit):", filter: (value) => value === 0 ? null : value },
      { type: "number", name: "mintFee", message: "Enter the mint fee (0 for none):", filter: (value) => value === 0 ? null : value },
      { type: "number", name: "royaltyNumerator", message: "Enter the royalty numerator:", default: 0 },
      { type: "number", name: "royaltyDenominator", message: "Enter the royalty denominator:", default: 10000 },
    ];
  const responses = await prompts(questions);

  const outJson: OutJson = {
      assetPath,
      collection: {
        name: collectionMetadata.name,
        description: collectionMetadata.description,
        uri: collectionMetadata.uri,
        mutableCollectionMetadata: responses.mutableCollectionMetadata,
        mutableTokenMetadata: responses.mutableTokenMetadata,
        randomMint: responses.randomMint,
        isSoulbound: responses.isSoulbound,
        tokensBurnableByCollectionOwner: responses.tokensBurnableByCollectionOwner,
        tokensTransferrableByCollectionOwner: responses.tokensTransferrableByCollectionOwner,
        maxSupply: responses.maxSupply,
        mintFee: responses.mintFee,
        royaltyNumerator: responses.royaltyNumerator,
        royaltyDenominator: responses.royaltyDenominator,
      },
      tokens: [],
  };

  // Process each token JSON file in the json folder
  const jsonFiles = glob.sync(resolvePath(assetPath, "json", "*.json"), { windowsPathsNoEscape: true });

  jsonFiles.forEach((filePath) => {
      if (path.basename(filePath) === "collection.json") return; // Skip the collection metadata file

      const tokenMetadata = JSON.parse(fs.readFileSync(filePath, "utf8"));
      
      // Ensure that `uri` exists in tokenMetadata and use it directly
      if (!tokenMetadata.uri) {
          console.warn(`URI missing in token metadata for ${path.basename(filePath)}. Skipping.`);
          return;
      }

      const token: TokenMetadata = {
        name: tokenMetadata.name,
        description: tokenMetadata.description,
        uri: tokenMetadata.uri,
      };

      outJson.tokens.push(token);
  });

  // Write the outJson to config.json
  await fs.promises.writeFile(
      configPath,
      JSON.stringify(outJson, null, 4),
      "utf8",
  );

  console.log("Preparing to create collections...");
  
  let collectionAddress: string;
  try {
    collectionAddress = await createEZLaunchCollection({
      creator: account,
      description: collectionMetadata.description,
      name: collectionMetadata.name,
      uri: collectionMetadata.uri,
      mutableCollectionMetadata: responses.mutableCollectionMetadata,
      mutableTokenMetadata: responses.mutableTokenMetadata,
      randomMint: responses.randomMint,
      isSoulbound: responses.isSoulbound,
      tokensBurnableByCollectionOwner: responses.tokensBurnableByCollectionOwner,
      tokensTransferrableByCollectionOwner: responses.tokensTransferrableByCollectionOwner,
      maxSupply: responses.maxSupply,
      mintFee: responses.mintFee,
      royaltyNumerator: responses.royaltyNumerator,
      royaltyDenominator: responses.royaltyDenominator,
    });
    console.log("Collection created at address:", collectionAddress);
  } catch (error) {
    throw new Error(`Failed to create collection: ${error}`);
  }

  console.log("Preparing to pre-mint tokens...");

  let tokenNames: string[] = [];
  let tokenUris: string[] = [];
  let tokenDescriptions: string[] = [];
  outJson.tokens.forEach((token) => {
      tokenNames.push(token.name);
      tokenUris.push(token.uri);
      tokenDescriptions.push(token.description);
  });

  try {
    await preMintTokens(account, collectionAddress!, tokenNames, tokenUris, tokenDescriptions);
    console.log("Successfully executed batch pre-minting tokens.");
  } catch (error) {
      throw new Error(`Failed to execute batch pre-minting tokens: ${error}`);
  }
}

  async function run() {
    program.parse();
  }

run();

