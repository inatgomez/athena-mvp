// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2015, 2016, 2017 Dapphub

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.8.26;

import { ERC20 } from "solady/tokens/ERC20.sol";
/// @notice Wrapped IP implementation.
/// @author Inspired by WETH9 (https://github.com/dapphub/ds-weth/blob/master/src/weth9.sol)
contract WIP is ERC20 {
    event  Deposit(address indexed from, uint amount);
    event  Withdrawal(address indexed to, uint amount);

    error IPTransferFailed();

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint value) external {
        _burn(msg.sender, value);
        (bool success, ) = msg.sender.call{value: value}("");
        if (!success) {
            revert IPTransferFailed();
        }
        emit Withdrawal(msg.sender, value);
    }

    function name() public view virtual override returns (string memory) {
        return "Wrapped IP";
    }

    function symbol() public view virtual override returns (string memory) {
        return "WIP";
    }

    function _givePermit2InfiniteAllowance() internal view override returns (bool) {
        return true;
    }
}