import colors from "colors";
import fs from "fs";
import path from "path";
import { program } from "commander";
import {
  Account,
  CommittedTransactionResponse,
  WriteSetChangeWriteResource,
} from "@aptos-labs/ts-sdk";
import prompts from "prompts";
import { uploadCollectionAndTokenAssets } from "./assetUploader";
import {
  CONTRACT_ADDRESS,
  claimToken,
  createEZLaunchCollection,
  preMintTokens,
  setMintingStatus,
} from "./contract";
import {
  OCTAS_PER_APT,
  OutJson,
  TokenMetadata,
  exitWithError,
  resolveConfigAddress,
  resolvePath,
  resolveProfile,
} from "./utils";

program
  .name("ez-launch")
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
  .requiredOption(
    "--profile <aptos-cli-profile>",
    "The profile name of the Aptos CLI.",
  )
  .requiredOption(
    "--asset-path <asset-path>",
    "The asset path. Format: '/path/to/assets', containing 'collection.png', 'collection.json', '/images' folder, and '/json' folder.",
  )
  .requiredOption(
    "--fund-amount <amount>",
    "The amount to fund to the decentralized storage for uploading.",
    parseFloat,
  )
  .action(
    async (options: {
      profile: string;
      assetPath: string;
      fundAmount: number;
    }) => {
      const { profile, assetPath, fundAmount } = options;
      const collectionMediaPath = `${assetPath}/collection.png`;
      const collectionMetadataJsonPath = `${assetPath}/collection.json`;
      const tokenMediaFolderPath = `${assetPath}/images`;
      const tokenMetadataJsonFolderPath = `${assetPath}/json`;

      const [account, network] = await resolveProfile(profile);

      const { collectionMetadataJsonURI, tokenMetadataJsonFolderURI } =
        await uploadCollectionAndTokenAssets(
          collectionMediaPath,
          collectionMetadataJsonPath,
          tokenMediaFolderPath,
          tokenMetadataJsonFolderPath,
          account,
          fundAmount * OCTAS_PER_APT,
          network,
        );

      console.log("Collection Metadata JSON URI:", collectionMetadataJsonURI);
      console.log(
        "Token Metadata JSON Folder URI:",
        tokenMetadataJsonFolderURI,
      );
      console.log(colors.green("Assets successfully uploaded."));
      process.exit();
    },
  );

program
  .command("create-collection")
  .description("Create a NFT collection with pre minted tokens.")
  .requiredOption("--name <name>", "Name of the NFT project.")
  .requiredOption("--profile <profile>", "The profile name of the Aptos CLI.")
  .requiredOption(
    "--asset-path <asset-path>",
    "The asset path. Format: '/path/to/assets', containing 'collection.png', 'collection.json', '/images' folder, and '/json' folder.",
  )
  .action(
    async (options: { profile: string; name: string; assetPath: string }) => {
      const { profile, name, assetPath } = options;

      try {
        const [account, network] = await resolveProfile(profile);
        console.log(
          `Profile ${profile} resolved for network ${network} with account address ${account.accountAddress}.`,
        );

        await createCollection(account, name, assetPath);
      } catch (error) {
        exitWithError(`Error creating collection: ${error}`);
      }
    },
  );

program
  .command("validate")
  .description("Validates the NFT collection configuration.")
  .option(
    "--project-path <project-path>",
    "Path to the NFT project directory.",
    ".",
  )
  .action(async (options: { projectPath: string }) => {
    const { projectPath } = options;
    await validateProjectConfig(projectPath);
  });

program
  .command("claim-token")
  .description("Claim tokens from an EZLaunch Collection.")
  .requiredOption("--profile <profile>", "The profile name of the Aptos CLI.")
  .requiredOption(
    "--ezlaunch-config-address <ezlaunchConfigAddress>",
    "EZLaunchConfig address",
  )
  .action(async (options) => {
    const { profile, ezlaunchConfigAddress } = options;

    try {
      const [account, network] = await resolveProfile(profile);
      console.log(
        `Profile ${profile} resolved for network ${network} with account address ${account.accountAddress}.`,
      );

      await claimToken(account, ezlaunchConfigAddress);
    } catch (error) {
      exitWithError(`Error claiming token: ${error}`);
    }
  });

program
  .command("set-minting-status")
  .description("Set minting status for an EZLaunch Collection.")
  .requiredOption("--profile <profile>", "The profile name of the Aptos CLI.")
  .requiredOption(
    "--ready-to-mint <readyToMint>",
    "Set the minting status true or false, default to true if not set",
    true,
  )
  .option(
    "--project-path <project-path>",
    "Path to the NFT project directory.",
    ".",
  )
  .option(
    "--ezlaunch-config-address <ezlaunchConfigAddress>",
    "EZLaunchConfig address",
  )
  .action(async (options) => {
    const { profile, readyToMint, projectPath, ezlaunchConfigAddress } =
      options;

    try {
      const [account, network] = await resolveProfile(profile);
      console.log(
        `Profile ${profile} resolved for network ${network} with account address ${account.accountAddress}.`,
      );

      const configAddress = await resolveConfigAddress(
        projectPath,
        ezlaunchConfigAddress,
      );

      await setMintingStatus(account, configAddress, readyToMint);
      console.log(`Minting status set to ${readyToMint} for ${configAddress}`);
    } catch (error) {
      exitWithError(`Error setting minting status: ${error}`);
    }
  });

async function validateProjectConfig(projectPath: string) {
  const fullPath = resolvePath(projectPath, "config.json");

  if (!fs.existsSync(fullPath)) {
    exitWithError(
      colors.red(
        "Error: The specified project path does not contain a config.json file.",
      ),
    );
  }
  const configBuf = fs.readFileSync(resolvePath(projectPath, "config.json"));
  const config = JSON.parse(configBuf.toString("utf8"));

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
    config.tokens.forEach(
      (token: { name: any; description: any; uri: any }, index: any) => {
        if (!token.name) {
          errors.push(`Token at index ${index} has no name.`);
        }
        if (!token.description) {
          errors.push(`Token at index ${index} has no description.`);
        }
        if (!token.uri) {
          errors.push(`Token at index ${index} has no URI.`);
        }
      },
    );
  }

  if (errors.length > 0) {
    exitWithError(colors.red("Errors found in config:"));
    errors.forEach((error) => exitWithError(error));
  }

  if (warnings.length > 0) {
    console.warn(colors.bgBlue("Warnings found in config:"));
    warnings.forEach((warning) => console.warn(warning));
  }

  if (errors.length === 0 && warnings.length === 0) {
    console.log("No issues found in config.");
  }
}

/**
 * /assets
    / collection.json
    / collection.png
    /images
      1.png
      2.png
      3.png
    /json
      1.json
      2.json
      3.json
*/
async function createCollection(
  account: Account,
  name: string,
  assetPath: string,
) {
  const fullPath = resolvePath(".", name);
  if (fs.existsSync(fullPath)) {
    console.log(`${fullPath} already exists, skipping creation.`);
  } else {
    fs.mkdirSync(fullPath, { recursive: true });
    console.log(`${fullPath} created.`);
  }

  const configPath = path.join(fullPath, "config.json");

  // Load the collection metadata from the provided URI
  const collectionMetadataPath = path.join(assetPath, "collection.json");
  const collectionMetadata = JSON.parse(
    fs.readFileSync(collectionMetadataPath, "utf8"),
  );

  const questions = [
    {
      type: "confirm",
      name: "mutableCollectionMetadata",
      message: "Is collection metadata mutable?",
      default: false,
    },
    {
      type: "confirm",
      name: "mutableTokenMetadata",
      message: "Is token metadata mutable?",
      default: false,
    },
    {
      type: "confirm",
      name: "randomMint",
      message: "Enable random mint?",
      default: false,
    },
    {
      type: "confirm",
      name: "isSoulbound",
      message: "Is the collection soulbound?",
      default: false,
    },
    {
      type: "confirm",
      name: "tokensBurnableByCollectionOwner",
      message: "Can tokens be burned by the collection owner?",
      default: false,
    },
    {
      type: "confirm",
      name: "tokensTransferrableByCollectionOwner",
      message: "Can tokens be transferred by the collection owner?",
      default: false,
    },
    {
      type: "number",
      name: "maxSupply",
      message: "Enter the maximum supply (0 for no limit):",
      filter: (value: number) => (value === 0 ? null : value),
    },
    {
      type: "number",
      name: "mintFee",
      message: "Enter the mint fee (0 for none):",
      filter: (value: number) => (value === 0 ? null : value),
    },
    {
      type: "number",
      name: "royaltyNumerator",
      message: "Enter the royalty numerator:",
      default: 0,
    },
    {
      type: "number",
      name: "royaltyDenominator",
      message: "Enter the royalty denominator:",
      default: 0,
    },
  ];
  const responses = await prompts(questions as any);

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
      tokensBurnableByCollectionOwner:
        responses.tokensBurnableByCollectionOwner,
      tokensTransferrableByCollectionOwner:
        responses.tokensTransferrableByCollectionOwner,
      maxSupply: responses.maxSupply,
      mintFee: responses.mintFee,
      royaltyNumerator: responses.royaltyNumerator,
      royaltyDenominator: responses.royaltyDenominator,
    },
    tokens: [],
    configAddress: "",
  };

  // Process each token JSON file in the json folder
  const resolvedJsonPath = resolvePath(assetPath, "json");
  const files = fs.readdirSync(resolvedJsonPath);
  const jsonFiles = files
    .filter((file) => path.extname(file) === ".json")
    .map((file) => path.join(resolvedJsonPath, file));

  jsonFiles.forEach((filePath: string) => {
    if (path.basename(filePath) === "collection.json") return; // Skip the collection metadata file
    const tokenMetadata = JSON.parse(fs.readFileSync(filePath, "utf8"));

    // Ensure that `uri` exists in tokenMetadata and use it directly
    if (!tokenMetadata.uri) {
      console.warn(
        `URI missing in token metadata for ${path.basename(filePath)}. Skipping.`,
      );
      return;
    }

    const token: TokenMetadata = {
      name: tokenMetadata.name,
      description: tokenMetadata.description,
      uri: tokenMetadata.uri,
    };

    outJson.tokens.push(token);
  });

  console.log("Preparing to create collections...");

  let txnResponse: CommittedTransactionResponse;
  try {
    txnResponse = await createEZLaunchCollection({
      creator: account,
      description: collectionMetadata.description,
      name: collectionMetadata.name,
      uri: collectionMetadata.uri,
      mutableCollectionMetadata: responses.mutableCollectionMetadata,
      mutableTokenMetadata: responses.mutableTokenMetadata,
      randomMint: responses.randomMint,
      isSoulbound: responses.isSoulbound,
      tokensBurnableByCollectionOwner:
        responses.tokensBurnableByCollectionOwner,
      tokensTransferrableByCollectionOwner:
        responses.tokensTransferrableByCollectionOwner,
      maxSupply: responses.maxSupply,
      mintFee: responses.mintFee,
      royaltyNumerator: responses.royaltyNumerator,
      royaltyDenominator: responses.royaltyDenominator,
    });
    console.log("Collection created at address:", txnResponse.hash);
  } catch (error) {
    throw new Error(`Failed to create collection: ${error}`);
  }

  const collectionConfigAddress = (
    txnResponse.changes.find(
      (wsc) =>
        (wsc as WriteSetChangeWriteResource).data.type ===
        `${CONTRACT_ADDRESS}::ez_launch::EZLaunchConfig`,
    ) as WriteSetChangeWriteResource
  ).address;

  outJson.configAddress = collectionConfigAddress;
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
    await preMintTokens(
      account,
      collectionConfigAddress!,
      tokenNames,
      tokenUris,
      tokenDescriptions,
    );
    console.log("Successfully executed batch pre-minting tokens.");
  } catch (error) {
    throw new Error(`Failed to execute batch pre-minting tokens: ${error}`);
  }

  // Write the outJson to config.json
  await fs.promises.writeFile(
    configPath,
    JSON.stringify(outJson, null, 4),
    "utf8",
  );
}

async function run() {
  program.parse();
}

run();
