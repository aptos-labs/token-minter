import os from "os";
import fs from "fs";
import path from "path";
import colors from "colors";
import { program } from "commander";
import YAML from "yaml";
import { exit } from "process";
import { Account, Aptos, AptosConfig, Ed25519PrivateKey, Network } from "@aptos-labs/ts-sdk";

export const aptosConfig = new AptosConfig({ network: process.env["NETWORK"] as Network ?? Network.TESTNET });
export const aptos = new Aptos(aptosConfig);

export interface TokenMetadata {
    name: string;
    description: string;
    uri: string;
}

export interface CollectionMetadata {
    name: string;
    description: string;
    uri: string;
    mutableCollectionMetadata: boolean;
    mutableTokenMetadata: boolean;
    randomMint: boolean;
    isSoulbound: boolean;
    tokensBurnableByCollectionOwner: boolean;
    tokensTransferrableByCollectionOwner: boolean;
    maxSupply: number | null;
    mintFee: number | null;
    royaltyNumerator: number;
    royaltyDenominator: number;
}

export interface OutJson {
    assetPath: string;
    collection: CollectionMetadata;
    tokens: TokenMetadata[];
}

export const OCTAS_PER_APT = 100_000_000;

export async function resolveProfile(
    profileName: string,
): Promise<[Account, Network]> {
    // Check if Aptos CLI config file exists
    const cliConfigFile = resolvePath(os.homedir(), ".aptos", "config.yaml");
    if (!fs.existsSync(cliConfigFile)) {
        throw new Error(
        "Cannot find the global config for Aptos CLI. Did you forget to run command 'aptos config set-global-config --config-type global && aptos init --profile <profile-name>'?",
        );
    }

    const configBuf = await fs.promises.readFile(cliConfigFile);
    const config = YAML.parse(configBuf.toString("utf8"));

    if (!config?.profiles?.[profileName]) {
        throw new Error(
        `Profile "${profileName}" is not found. Run command "aptos config show-global-config" to make sure the config type is "Global". Run command "aptos config show-profiles" to see available profiles.`,
        );
    }

    const profile = config.profiles[profileName];

    if (!profile.private_key || !profile.rest_url) {
        throw new Error(`Profile "${profileName}" format is invalid.`);
    }

    let network = "";

    if (profile.rest_url.includes(Network.TESTNET)) {
        network = Network.TESTNET;
    }

    if (profile.rest_url.includes(Network.MAINNET)) {
        network = Network.MAINNET;
    }

    if (network !== Network.TESTNET && network !== Network.MAINNET) {
        throw new Error(
        `Make sure profile "${profileName}" points to "${Network.TESTNET}" or "${Network.MAINNET}". Run command "aptos config show-profiles --profile ${profileName}" to see profile details.`,
        );
    }

        return [
        Account.fromPrivateKey({ privateKey: new Ed25519PrivateKey(profile.private_key)}),
        network,
    ];
}

export function readProjectConfig(project: string): any {
    const projectPath = project || ".";
  
    const configBuf = fs.readFileSync(resolvePath(projectPath, "config.json"));
  
    return JSON.parse(configBuf.toString("utf8"));
  }

  process.on("uncaughtException", (err: Error) => {
    if (program.opts().verbose) {
      console.error(err);
    }
  
    exitWithError(err.message);
  });

  export function exitWithError(message: string) {
    console.error(colors.red(message));
    exit(1);
  }
  
  export function resolvePath(p: string, ...rest: string[]): string {
      if (!p) return "";
      return path.resolve(expandTilde(p), ...rest);
  }
  

  export function expandTilde(filePath) {
    if (!filePath.startsWith('~')) {
      return filePath;
    }
    const homeDirectory = os.homedir();
    if (filePath === '~') {
      return homeDirectory;
    }
    return path.join(homeDirectory, filePath.slice(2));
  }
  