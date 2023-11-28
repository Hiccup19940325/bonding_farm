// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PrincipalToken is ERC20 {
    string private constant NANE = "Principal Token";
    string private constant SYMBOL = "PT";

    constructor() ERC20(NANE, SYMBOL) {}

    function mint(address account, uint amount) external virtual {
        _mint(account, amount);
    }
}
