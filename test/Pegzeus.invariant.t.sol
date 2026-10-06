// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Pegzeus} from "../src/Pegzeus.sol";

/// @dev A closed set of holders and an independent balance/allowance model.
contract PegzeusHandler is Test {
    Pegzeus public immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCA401), address(0xDA7E1)];
    uint256[4] public expectedBalances;
    uint256[4][4] public expectedAllowances;

    constructor(Pegzeus token_) {
        token = token_;
        expectedBalances[0] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        uint256 from = fromSeed % 4;
        uint256 to = toSeed % 4;
        amount = bound(amount, 0, expectedBalances[from]);
        vm.prank(actors[from]);
        assertTrue(token.transfer(actors[to], amount));
        expectedBalances[from] -= amount;
        expectedBalances[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        // Exercise both finite replacement/revocation and unlimited allowances.
        if (amount != 0) {
            amount = amount % 8 == 0 ? type(uint256).max : bound(amount, 0, 1_000_000_000 * 10 ** 18);
        }
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowances[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        uint256 from = fromSeed % 4;
        uint256 to = toSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 allowance = expectedAllowances[from][spender];
        uint256 maximum = expectedBalances[from] < allowance ? expectedBalances[from] : allowance;
        amount = bound(amount, 0, maximum);
        vm.prank(actors[spender]);
        assertTrue(token.transferFrom(actors[from], actors[to], amount));
        expectedBalances[from] -= amount;
        expectedBalances[to] += amount;
        if (allowance != type(uint256).max) expectedAllowances[from][spender] -= amount;
    }
}

contract PegzeusInvariantTest is Test {
    Pegzeus private token;
    PegzeusHandler private handler;

    function setUp() public {
        token = new Pegzeus();
        handler = new PegzeusHandler(token);
        token.transfer(handler.actors(0), token.totalSupply());

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = PegzeusHandler.transfer.selector;
        selectors[1] = PegzeusHandler.approve.selector;
        selectors[2] = PegzeusHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyBalancesAndAllowancesMatchModel() public view {
        uint256 accountedSupply;
        for (uint256 i; i < 4; ++i) {
            uint256 balance = token.balanceOf(handler.actors(i));
            assertEq(balance, handler.expectedBalances(i));
            accountedSupply += balance;
            for (uint256 j; j < 4; ++j) {
                assertEq(token.allowance(handler.actors(i), handler.actors(j)), handler.expectedAllowances(i, j));
            }
        }
        assertEq(accountedSupply, 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), accountedSupply);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }
}
