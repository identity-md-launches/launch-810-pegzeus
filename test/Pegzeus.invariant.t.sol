// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
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
            amount = amount % 8 == 0 ? type(uint256).max : bound(amount, 0, type(uint256).max - 1);
        }
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowances[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) public {
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

    /// @dev Always reaches a positive delegated transfer, even when random approvals are sparse.
    function approveAndSpend(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount, bool unlimited)
        external
    {
        uint256 from = _fundedActor(fromSeed);
        uint256 spender = spenderSeed % 4;
        amount = bound(amount, 1, expectedBalances[from]);
        _approveExact(from, spender, unlimited ? type(uint256).max : amount);
        transferFrom(from, toSeed, spender, amount);
    }

    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        uint256 from = fromSeed % 4;
        uint256 balance = expectedBalances[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[from], balance, amount)
        );
        vm.prank(actors[from]);
        token.transfer(actors[toSeed % 4], amount);
        // No ghost update: the invariant checks that every balance and allowance stayed unchanged.
    }

    function rejectTransferFromAboveBalance(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 amount,
        bool unlimited
    ) external {
        uint256 from = fromSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 balance = expectedBalances[from];
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        _approveExact(from, spender, unlimited ? type(uint256).max : amount);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[from], balance, amount)
        );
        vm.prank(actors[spender]);
        token.transferFrom(actors[from], actors[toSeed % 4], amount);
        // In particular, a reverted transfer must roll back any finite allowance consumption.
    }

    function rejectUnapprovedTransferFrom(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 amount,
        uint256 allowanceSeed
    ) external {
        uint256 from = _fundedActor(fromSeed);
        uint256 spender = spenderSeed % 4;
        amount = bound(amount, 1, expectedBalances[from]);
        uint256 allowance = bound(allowanceSeed, 0, amount - 1);
        _approveExact(from, spender, allowance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], allowance, amount)
        );
        vm.prank(actors[spender]);
        token.transferFrom(actors[from], actors[toSeed % 4], amount);
    }

    function rejectZeroRecipient(uint256 fromSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        uint256 from = fromSeed % 4;
        amount = bound(amount, 0, expectedBalances[from]);
        if (delegated) {
            uint256 spender = spenderSeed % 4;
            _approveExact(from, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(actors[spender]);
            token.transferFrom(actors[from], address(0), amount);
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(actors[from]);
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actors[ownerSeed % 4]);
        token.approve(address(0), amount);
    }

    function revokeAndReject(uint256 fromSeed, uint256 spenderSeed) external {
        uint256 from = _fundedActor(fromSeed);
        uint256 spender = spenderSeed % 4;
        _approveExact(from, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], 0, 1));
        vm.prank(actors[spender]);
        token.transferFrom(actors[from], actors[(from + 1) % 4], 1);
    }

    function _approveExact(uint256 owner, uint256 spender, uint256 amount) private {
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowances[owner][spender] = amount;
    }

    function _fundedActor(uint256 seed) private view returns (uint256) {
        for (uint256 i; i < 4; ++i) {
            uint256 actor = (seed % 4 + i) % 4;
            if (expectedBalances[actor] > 0) return actor;
        }
        revert("closed actor set lost its supply");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract PegzeusInvariantTest is Test {
    Pegzeus private token;
    PegzeusHandler private handler;

    function setUp() public {
        token = new Pegzeus();
        handler = new PegzeusHandler(token);
        token.transfer(handler.actors(0), token.totalSupply());

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = PegzeusHandler.transfer.selector;
        selectors[1] = PegzeusHandler.approve.selector;
        selectors[2] = PegzeusHandler.transferFrom.selector;
        selectors[3] = PegzeusHandler.approveAndSpend.selector;
        selectors[4] = PegzeusHandler.rejectTransferAboveBalance.selector;
        selectors[5] = PegzeusHandler.rejectTransferFromAboveBalance.selector;
        selectors[6] = PegzeusHandler.rejectUnapprovedTransferFrom.selector;
        selectors[7] = PegzeusHandler.rejectZeroRecipient.selector;
        selectors[8] = PegzeusHandler.rejectZeroSpender.selector;
        selectors[9] = PegzeusHandler.revokeAndReject.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyBalancesAndAllowancesMatchModel() public view {
        uint256 accountedSupply;
        for (uint256 i; i < 4; ++i) {
            uint256 balance = token.balanceOf(handler.actors(i));
            assertEq(balance, handler.expectedBalances(i));
            accountedSupply += balance;
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
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
