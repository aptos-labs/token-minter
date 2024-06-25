use anyhow::{Context, Result};
use aptos_logger::{Level, Logger};
use aptos_sdk::{
    transaction_builder::TransactionFactory,
    move_types::account_address::AccountAddress,
    types::AccountKey,
};    
use aptos_transaction_emitter_lib::{Cluster, emitter::load_specific_account};
use clap::{Parser, Subcommand};
use aptos_config::keys::ConfigKey;
use aptos_crypto::ed25519::Ed25519PrivateKey;

use aptos_experimental_bulk_txn_submit::{coordinator::{create_sample_addresses, execute_return_worker_funds, execute_submit, CreateSampleAddresses, SubmitArgs}, workloads::{create_account_address_pairs_work, create_account_addresses_work}};
use its_aptos_thing::{create_test_collection, NftBurnSignedTransactionBuilder, NftMintSignedTransactionBuilder};

mod its_aptos_thing;

#[derive(Parser, Debug)]
struct Args {
    #[clap(subcommand)]
    command: BulkMintCommand,
}

#[derive(Subcommand, Debug)]
enum BulkMintCommand {
    Submit(Submit),
    CreateSampleAddresses(CreateSampleAddresses),
}

#[derive(Parser, Debug)]
pub struct Submit {
    #[clap(flatten)]
    submit_args: SubmitArgs,
    #[clap(subcommand)]
    work_args: WorkTypeSubcommand,
}

#[derive(Subcommand, Debug)]
pub enum WorkTypeSubcommand {
    NftMint(NftMintArgs),
    NftBurn(NftBurnArgs),
    ReturnWorkerFunds,
}

#[derive(Parser, Debug)]
pub struct NftMintArgs {
    #[clap(long)]
    contract_address: AccountAddress,

    #[clap(long, default_value = "only_on_aptos")]
    contract_module_name: String,

    #[clap(long, default_value = "mint_to_recipient")]
    mint_entry_fun: String,

    #[clap(long)]
    collection_address: AccountAddress,

    #[clap(long)]
    destinations_file: String,
}

#[derive(Parser, Debug)]
pub struct NftBurnArgs {
    #[clap(long)]
    contract_address: AccountAddress,

    #[clap(long, default_value = "only_on_aptos")]
    contract_module_name: String,
    
    #[clap(long, default_value = "burn_with_admin_worker")]
    burn_entry_fun: String,

    #[clap(long)]
    destinations_file: String,

    #[clap(long, value_parser = ConfigKey::<Ed25519PrivateKey>::from_encoded_string)]
    admin_key: ConfigKey<Ed25519PrivateKey>,
}

#[tokio::main]
pub async fn main() -> Result<()> {
    Logger::builder().level(Level::Info).build();

    let args = Args::parse();

    match args.command {
        BulkMintCommand::Submit(args) => create_work_and_execute(args).await,
        BulkMintCommand::CreateSampleAddresses(args) => create_sample_addresses(args),
    }
}

async fn create_work_and_execute(args: Submit) -> Result<()> {
    let cluster = Cluster::try_from_cluster_args(&args.submit_args.cluster_args)
        .await
        .context("Failed to build cluster")?;
    let coin_source_account = cluster
        .load_coin_source_account(&cluster.random_instance().rest_client())
        .await?;

    match &args.work_args {
        WorkTypeSubcommand::NftMint(mint_args) => {
            // create test collection:
             
            // let client = &cluster.random_instance().rest_client();
            // let admin_account = load_specific_account(
            //     AccountKey::from_private_key(mint_args.admin_key.private_key()),
            //     false,
            //     client,
            // )
            // .await?;

            // let txn_factory = args.submit_args.transaction_factory_args.with_init_params(
            //     TransactionFactory::new(cluster.chain_id));
            // let collection_owner_address = create_test_collection(
            //    mint_args.contract_address,
            //     admin_account,
            //    client,
            //     txn_factory.clone(),
            // ).await?;


            let work = create_account_addresses_work(&mint_args.destinations_file, false)?;
            let builder =
                NftMintSignedTransactionBuilder::new(mint_args.contract_address, &mint_args.contract_module_name, &mint_args.mint_entry_fun, mint_args.collection_address);
            execute_submit(work, args.submit_args, builder, cluster, coin_source_account).await
        },
        WorkTypeSubcommand::NftBurn(burn_args) => {
            let work = create_account_address_pairs_work(&burn_args.destinations_file, true).await?;

            let client = &cluster.random_instance().rest_client();
            let admin_account = load_specific_account(
                AccountKey::from_private_key(burn_args.admin_key.private_key()),
                false,
                client,
            )
            .await?;

            let builder = NftBurnSignedTransactionBuilder::new(burn_args.contract_address, &burn_args.contract_module_name, &burn_args.burn_entry_fun, admin_account);
            execute_submit(work, args.submit_args, builder, cluster, coin_source_account).await
        },
        WorkTypeSubcommand::ReturnWorkerFunds => {
            execute_return_worker_funds(args.submit_args, cluster, &coin_source_account).await
        },
    }
}
