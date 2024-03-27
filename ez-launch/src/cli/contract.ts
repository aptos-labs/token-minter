import { Account, Bool, InputGenerateTransactionOptions, InputGenerateTransactionPayloadData, MoveOption, MoveString, TransactionWorkerEventsEnum, U64 } from "@aptos-labs/ts-sdk";
import { aptos } from "./utils";

const CONTRACT_ADDRESS = process.env["CONTRACT_ADDRESS"];

export async  function createEZLaunchCollection(args: {
    creator: Account;
    description: string;
    name: string;
    uri: string;
    mutableCollectionMetadata: boolean;
    mutableTokenMetadata: boolean;
    randomMint: boolean;
    isSoulbound: boolean;
    tokensBurnableByCollectionOwner: boolean;
    tokensTransferrableByCollectionOwner: boolean;
    maxSupply?: string;
    mintFee?: string;
    royaltyNumerator?: string;
    royaltyDenominator?: string;
    options?: InputGenerateTransactionOptions;
  }): Promise<string> {
    const {
      creator,
      description,
      name,
      uri,
      mutableCollectionMetadata,
      mutableTokenMetadata,
      randomMint,
      isSoulbound,
      tokensBurnableByCollectionOwner,
      tokensTransferrableByCollectionOwner,
      maxSupply,
      mintFee,
      royaltyNumerator,
      royaltyDenominator,
      options,
    } = args;
  
    const pendingTxnHash = await buildAndSubmitTransaction(
      creator,
      "create_collection",
      [
        new MoveString(description),
        new MoveString(name),
        new MoveString(uri),
        new Bool(mutableCollectionMetadata),
        new Bool(mutableTokenMetadata),
        new Bool(randomMint),
        new Bool(isSoulbound),
        new Bool(tokensBurnableByCollectionOwner),
        new Bool(tokensTransferrableByCollectionOwner),
        new MoveOption(maxSupply ? new U64(BigInt(maxSupply)): null),
        new MoveOption(mintFee ? new U64(BigInt(mintFee)): null),
        new MoveOption(royaltyNumerator ? new U64(BigInt(royaltyNumerator)): null),
        new MoveOption(royaltyDenominator ? new U64(BigInt(royaltyDenominator)): null),
      ],
      options,
    );
  
    const response = await aptos.waitForTransaction({
      transactionHash: pendingTxnHash,
    });
  
    return response.hash;
}

export async function preMintTokens(account: Account, collectionAddress: string, tokenNames: string[], tokenUris: string[], tokenDescriptions: string[], batchSize: number = 50): Promise<void> {
    const payloads: InputGenerateTransactionPayloadData[] = [];

    // Create batches based on the batchSize and prepare payloads for each batch
    for (let i = 0; i < tokenNames.length; i += batchSize) {
        const end = i + batchSize < tokenNames.length ? i + batchSize : tokenNames.length;

        // Create a payload for each batch of tokens
        payloads.push({
            function: `${CONTRACT_ADDRESS}::ez_launch::pre_mint_tokens`,
            functionArguments: [
                collectionAddress,
                tokenNames.slice(i, end),
                tokenUris.slice(i, end),
                tokenDescriptions.slice(i, end),
                end - i, // The actual number of tokens in this batch
            ],
        });
    }

    aptos.transaction.batch.forSingleAccount({ sender: account, data: payloads });

    aptos.transaction.batch.on(TransactionWorkerEventsEnum.ExecutionFinish, async (data) => {
        console.log("Batch pre-minting finished", data);

        // Cleanup listeners once all batches are processed
        aptos.transaction.batch.removeAllListeners();
    });
}

async function buildAndSubmitTransaction(
    account: Account,
    functionName: string,
    functionArgs: any[],
    options?: InputGenerateTransactionOptions,
  ): Promise<string> {
    const transaction = await aptos.transaction.build.simple({
      sender: account.accountAddress,
      data: {
        function: `${CONTRACT_ADDRESS}::ez_launch::${functionName}`,
        functionArguments: functionArgs,
      },
      options,
    });
    const pendingTxn = await aptos.signAndSubmitTransaction({
      signer: account,
      transaction,
    });
    return pendingTxn.hash;
  }