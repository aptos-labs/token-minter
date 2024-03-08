# example-permit

This example shows how a mint can be gated by a ED25519 signature.

How to setup:

1. Deploy minter
2. Deploy example_permit
3. Call `init` with the deployer in explorer
4. `npm i`
5. Update the PRIVATE_KEY, CONTRACT_ADDR, and MINT_TO_ADDR in index.js
6. `node index.js`. Copy the proof
7. Call `mint_with_permit` with any account in the explorer
  a. NOTE: Look at the `MintPermit` signed in `index.js` to get all the params
