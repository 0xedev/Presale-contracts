forge script script/DeployPresale.s.sol --rpc-url $BASE_MAINNET_HTTPS --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $BASESCAN_API_KEY -vvvv

forge script script/CreatePresale.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv

forge script script/DeployMyToken.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv

forge script --tc script/FinalizePresaleScript.s.sol --rpc-url $BASE_MAINNET_HTTPS --private-key $PRIVATE_KEY

# To load the variables in the .env file

source .env
