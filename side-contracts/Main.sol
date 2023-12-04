// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Token is ERC20, Ownable {
    uint256 maxSupply = 10000000000 * 10 ** 18;

    address burnAddress;

    constructor() ERC20("Balawayne", "BALA") {
        _mint(msg.sender, maxSupply);
    }
}
