// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

use anyhow::Result;
use aptos_experimental_bulk_txn_submit::{event_lookup::{get_burn_token_addr, get_mint_token_addr, search_single_event_data}, workloads::{rand_string, SignedTransactionBuilder}};
use aptos_logger::info;
use aptos_sdk::{
    move_types::{account_address::AccountAddress, ident_str, identifier::{IdentStr, Identifier}, language_storage::ModuleId},
    rest_client::{aptos_api_types::TransactionOnChainData, Client},
    transaction_builder::TransactionFactory,
    types::{
        transaction::{EntryFunction, SignedTransaction},
        LocalAccount,
    },
};
use serde::{Deserialize, Serialize};

fn get_module_id(contract_address: AccountAddress, contract_module_name: &str) -> ModuleId {
    ModuleId::new(
        contract_address,
        IdentStr::new(contract_module_name).unwrap().to_owned(),
    )
}

#[derive(Debug, Serialize, Deserialize)]
struct CreateCollectionConfigMoveStruct {
    collection_config: AccountAddress,
    collection: AccountAddress,
    ready_to_mint: bool,
}

pub async fn create_test_collection(
    contract_address: AccountAddress,
    contract_module_name: &str,
    admin_account: LocalAccount,
    client: &Client,
    txn_factory: TransactionFactory,
) -> Result<AccountAddress> {
    let contract_module = get_module_id(contract_address, contract_module_name);

    let collection_name = format!("Test Collection {}", rand_string(10));

    let create_collection_txn = admin_account.sign_with_transaction_builder(
        txn_factory.entry_function(EntryFunction::new(
            contract_module.clone(),
            ident_str!("create_collection").to_owned(),
            vec![],
            vec![
                bcs::to_bytes(&collection_name).unwrap(), // collection_name
                bcs::to_bytes(&"collection description").unwrap(),              // collection_description
                bcs::to_bytes(&"htpps://some.collection.uri.test").unwrap(),              // collection_uri
                bcs::to_bytes(&"test token #").unwrap(),  // token_name_prefix
                bcs::to_bytes(&"test token description").unwrap(),              // token_description
                bcs::to_bytes(&vec!["htpps://some.uri1.test", "htpps://some.uri2.test"]).unwrap(), // token_uris: vector<String>,
                bcs::to_bytes(&vec![10u64, 1u64]).unwrap(), // token_uris_weights: vector<u64>,
                bcs::to_bytes(&true).unwrap(),           // mutable_collection_metadata
                bcs::to_bytes(&true).unwrap(),           // mutable_token_metadata
                bcs::to_bytes(&true).unwrap(),            // tokens_burnable_by_collection_owner
                bcs::to_bytes(&false).unwrap(), // tokens_transferrable_by_collection_owner
                bcs::to_bytes(&Some(1000000u64)).unwrap(), // max_supply
                bcs::to_bytes(&Option::<u64>::None).unwrap(), // royalty_numerator
                bcs::to_bytes(&Option::<u64>::None).unwrap(), // royalty_denominator
            ],
        )),
    );

    let output = client
        .submit_and_wait_bcs(&create_collection_txn)
        .await?
        .into_inner();
    assert!(output.info.status().is_success(), "{:?}", output);
    info!("create_collection txn: {:?}", output.info);
    let create_collection_event: CreateCollectionConfigMoveStruct = search_single_event_data(
        &output.events,
        &format!("{}::CreateCollectionConfig", contract_module),
    )?;

    let collection_owner_address = create_collection_event.collection_config;

    let start_minting_txn = admin_account.sign_with_transaction_builder(
        txn_factory.entry_function(EntryFunction::new(
            contract_module.clone(),
            ident_str!("set_minting_status").to_owned(),
            vec![],
            vec![
                bcs::to_bytes(&collection_owner_address).unwrap(),
                bcs::to_bytes(&true).unwrap(),
            ],
        )),
    );
    let output = client
        .submit_and_wait_bcs(&start_minting_txn)
        .await?
        .into_inner();
    assert!(output.info.status().is_success(), "{:?}", output);
    info!("set_minting_status txn: {:?}", output.info);

    info!("collection_owner_address: {:?}", collection_owner_address);

    Ok(collection_owner_address)
} 

pub struct NftMintSignedTransactionBuilder {
    contract_module: ModuleId,
    mint_entry_fun: Identifier,
    collection_owner_address: AccountAddress,
}

impl NftMintSignedTransactionBuilder {
    pub fn new(
        contract_address: AccountAddress,
        contract_module_name: &str,
        mint_entry_fun: &str,
        collection_owner_address: AccountAddress,
    ) -> Self {
        Self {
            contract_module: get_module_id(contract_address, contract_module_name),
            mint_entry_fun: IdentStr::new(mint_entry_fun).unwrap().to_owned(),
            collection_owner_address,
        }
    }
}

impl SignedTransactionBuilder<AccountAddress> for NftMintSignedTransactionBuilder {
    fn build(
        &self,
        data: &AccountAddress,
        account: &LocalAccount,
        txn_factory: &TransactionFactory,
    ) -> SignedTransaction {
        account.sign_with_transaction_builder(
            txn_factory.entry_function(EntryFunction::new(
                self.contract_module.clone(),
                self.mint_entry_fun.clone(),
                vec![],
                vec![
                    bcs::to_bytes(&self.collection_owner_address).unwrap(), // collection_config_object
                    bcs::to_bytes(data).unwrap(), // recipient
                ],
            )),
        )
    }

    fn success_output(&self, data: &AccountAddress, txn_out: &Option<TransactionOnChainData>) -> String {
        let (status, token) = match txn_out {
            Some(txn_out) => match get_mint_token_addr(&txn_out.events) {
                Ok(dst) => ("success".to_string(), dst.to_standard_string()),
                Err(e) => (e.to_string(), "".to_string()),
            },
            None => ("missing".to_string(), "".to_string()),
        };
        format!(
            "{}\t{}\t{}\t{}",
            token,
            self.collection_owner_address.to_standard_string(),
            data,
            status
        )
    }
}

pub struct NftBurnSignedTransactionBuilder {
    admin_account: LocalAccount,
    contract_module: ModuleId,
    burn_entry_fun: Identifier,
}

impl NftBurnSignedTransactionBuilder {
    pub fn new(
        contract_address: AccountAddress,
        contract_module_name: &str,
        burn_entry_fun: &str,
        admin_account: LocalAccount, 
    ) -> Self {
        Self {
            admin_account,
            contract_module: get_module_id(contract_address, contract_module_name),
            burn_entry_fun: IdentStr::new(burn_entry_fun).unwrap().to_owned(),
        }
    }
}

impl SignedTransactionBuilder<(AccountAddress, AccountAddress)>
    for NftBurnSignedTransactionBuilder
{
    fn build(
        &self,
        data: &(AccountAddress, AccountAddress),
        account: &LocalAccount,
        txn_factory: &TransactionFactory,
    ) -> SignedTransaction {
        account.sign_multi_agent_with_transaction_builder(
            vec![&self.admin_account],
            txn_factory.entry_function(EntryFunction::new(
                self.contract_module.clone(),
                self.burn_entry_fun.clone(),
                vec![],
                vec![
                    bcs::to_bytes(&data.1).unwrap(), // collection_config_object
                    bcs::to_bytes(&data.0).unwrap(), // token
                ],
            )),
        )
    }

    fn success_output(
        &self,
        data: &(AccountAddress, AccountAddress),
        txn_out: &Option<TransactionOnChainData>,
    ) -> String {
        let (status, refund_addr) = match txn_out {
            Some(txn_out) => match get_burn_token_addr(&txn_out.events) {
                Ok(_dst) => (
                    "success".to_string(),
                    txn_out
                        .transaction
                        .try_as_signed_user_txn()
                        .unwrap()
                        .sender()
                        .to_standard_string(),
                ),
                Err(e) => (e.to_string(), "".to_string()),
            },
            None => ("missing".to_string(), "".to_string()),
        };
        format!(
            "{}\t{}\t{}\t{}",
            refund_addr,
            data.0.to_standard_string(),
            data.1.to_standard_string(),
            status
        )
    }
}
