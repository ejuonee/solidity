require('@nomicfoundation/hardhat-toolbox');
require('dotenv').config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: '0.8.18',
  networks: {
    sepolia: {
      url: process.env.INFURA_SEPOLIA_ENDPOINT,
      accounts: [process.env.PRIVATE_KEY_DEV],
    },
    ethereum: {
      url: process.env.INFURA_ETHEREUM_ENDPOINT,
      accounts: [process.env.PRIVATE_KEY_DEV],
    },
    arbitrum: {
      url: process.env.INFURA_ARBITRUM_ENDPOINT,
      accounts: [process.env.PRIVATE_KEY_DEV],
    },
    arbitestnet: {
      url: process.env.INFURA_ARBIGOERLI_ENDPOINT,
      accounts: [process.env.PRIVATE_KEY_DEV],
    },
  },
};
