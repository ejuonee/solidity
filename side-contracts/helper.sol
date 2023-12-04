function renounceOwnership() public virtual isOwner {
    require(_newOwner != address(0), "Ownable: new owner is the zero address");
    emit OwnershipTransferred(owner, _newOwner);
    owner = payable(_newOwner);
}

function burn(uint256 value) external {
    _burn(burnAdress, value);
    ammountBurnt += value;
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
                "Not Owner or burn address"
            );
            return;
        } else {
            require(
                super.balanceOf(to) + amount <= maxHoldingAmount,
                "Max Holding Ammount exceeded"
            );
        }
    }

    uint256 public maxHoldingAmount = (maxSupply / 100);