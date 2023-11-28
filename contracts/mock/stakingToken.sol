// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StakingToken is ERC20 {
    string private constant NANE = "Staking Token";
    string private constant SYMBOL = "ST";

    constructor() ERC20(NANE, SYMBOL) {}

    function mint(address account, uint amount) external virtual {
        _mint(account, amount);
    }
}
