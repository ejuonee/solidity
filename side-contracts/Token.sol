// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Token is ERC20, Ownable {
    using SafeMath for uint256;

    address public uniswapPair;
    address public burnAddress;
    address public operationsAndMarketingWallet;

    uint256 public devAndMarketingFee = 3; // 3%
    uint256 public burnFee = 1; // 1%
    uint256 _decimals = 18;
    uint256 ammountBurnt;
    uint256 TotalSupply = 1000000000 * 10 ** _decimals;
    uint256 public maxHoldingAmount = TotalSupply.div(100);

    string private _name = "CONSTANZE";
    string private _symbol = "CONNI";

    constructor() ERC20(_name, _symbol) {
        operationsAndMarketingWallet = msg.sender;
        _mint(owner(), TotalSupply);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (to == owner()) {
            //The new owner would be set to a burn wallet allowing only this wallet hold above 1%
            //This also allows initial minting to contract creator without max wallet applied
            require(
                from == owner() || to == owner() || to == burnAddress,
                "Not Owner"
            );
            return;
        } else {
            require(
                super.balanceOf(to) + amount <= maxHoldingAmount,
                "Max amount exceeded"
            );
        }
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        // Make sure sender has enough money to send
        uint256 senderBalance = balanceOf(msg.sender);
        require(senderBalance >= amount, "Not enough balance for transfer");

        //Take out a 3% tax
        uint256 taxAmount = amount.mul(devAndMarketingFee).div(100);
        uint256 burnAmount = amount.div(100);
        uint256 totalFees = taxAmount.add(burnAmount);
        uint256 transferAmount = amount - totalFees;

        // Transfer 97% to the  recipient
        // Called from Parent Contract
        _transfer(msg.sender, to, transferAmount);
        _transfer(msg.sender, operationsAndMarketingWallet, taxAmount);
        _transfer(msg.sender, burnAddress, burnAmount);

        ammountBurnt += burnAmount;

        // Emit the Transfer event
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function setBurnAdress(address _burnAddress) external onlyOwner {
        burnAddress = _burnAddress;
    }

    function setDevAndMarketingWallet(address _devWallet) public onlyOwner {
        operationsAndMarketingWallet = _devWallet;
    }

    function setUniswapPair(address _uniswapPair) external onlyOwner {
        uniswapPair = _uniswapPair;
    }
}
