// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IRoutePrim} from "./IRoutePrim.sol";

/// @title IBatchRouter
/// @notice Interface for executing multiple RoutePrim routes atomically in a single call
/// @dev All legs share the same transaction — if any leg fails the entire batch reverts.
interface IBatchRouter {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct BatchLeg {
        IRoutePrim.RouteParams route;
        IRoutePrim.AuthParams  auth;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event BatchRouted(address indexed initiator, uint256 legCount, uint256[] amountsOut);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error EmptyBatch();
    error BatchLegFailed(uint256 index);

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute a batch of route() calls atomically
    /// @param  legs     Array of (RouteParams, AuthParams) pairs; must be non-empty
    /// @return amountsOut Output amount for each leg, in order
    function batchRoute(BatchLeg[] calldata legs)
        external
        returns (uint256[] memory amountsOut);

    /// @notice Execute a batch of routeNative() calls; msg.value must equal the sum of all amountIns
    /// @param  legs     Array of (RouteParams, AuthParams) pairs for native BNB legs
    /// @return amountsOut Output amount for each leg, in order
    function batchRouteNative(BatchLeg[] calldata legs)
        external
        payable
        returns (uint256[] memory amountsOut);
}
