%% This file should work independent of which axis is being considered..

%%
% feedback policy K_t used for terminal set computations:
K_t = -dlqr(A, B, Q, maxadm_controlweight*R);

%==========================================================================
% Define a nominal feedback policy K and corresponding terminal cost
% Feedback policy chosen using discrete time linear quadratic regulator.
% This can be changed based on engineering preference:
K = -dlqr(A, B, Q, dlqr_controlweight*R);

% Terminal cost chosen as solution to DARE
P = dare(A+B*K, B, Q, dlqr_controlweight*R);


% count the length of the constraints on input, states, and uncertainty:

length_Fu = length(h_u);
length_Fx = length(h_x);
length_Fg = length(h_g);

%% State constraints:
% Points that after (A+B*K_t) get to (F_x,h_x) \ominus (F_g,h_g)
[F_x_g, h_x_g] = double(polytope(F_x, h_x) - polytope(F_g, h_g));
Fx{1} = F_x;
fx{1} = h_x;
for i=2:N
    Fx{i} = F_x;
    fx{i} = h_x;
end
for i=1:N
   Fu{i} = F_u;
   fu{i} = h_u;
end




%%
%==========================================================================
% Generate steady-state parameterization and their projection matrices
%==========================================================================

M = [A - eye(n), B, zeros(n,o); ...
    C, zeros(o,m), -eye(o)];
V = null(M);
LAMBDA = V(1:n,:);
PSI = V(n+1:n+m,:);
XI = V(n+m+1:n+m+o,:);

% Solutions of M*[x;u;y] = [-d;0] are of the form
% M\[-d;0] + V*theta, theta in R^m
V_0 = M\[-d_0; zeros(o,1)];
LAMBDA_0 = V_0(1:n);
PSI_0 = V_0(n+1:n+m);
XI_0 = V_0(n+m+1:n+m+o);

% these 2 are not used but we'll keep 'em for now..
Proj_X_t = LAMBDA*pinv(LAMBDA);
Proj_U_t = PSI*pinv(LAMBDA);

%%
%==========================================================================
% Compute maximally invariant set
%==========================================================================

disp('Computing and simplifying terminal set...');
F_w = [F_x zeros(length_Fx, m);
    zeros(length_Fx, n) F_x*LAMBDA; ...
    F_u*K_t, F_u*(PSI - K_t*LAMBDA); ...
    zeros(length_Fu, n) F_u*PSI; ...
    F_x_g*(A+B*K_t) F_x_g*B*(PSI-K_t*LAMBDA)];
h_w = [...
    h_x; ...
    h_x - F_x*LAMBDA_0; ...
    h_u - F_u*(PSI_0 - K_t*LAMBDA_0); ...
    h_u - F_u*PSI_0; ...
    h_x_g - F_x_g*B*(PSI_0-K_t*LAMBDA_0)];




% Subtract out points due to disturbance (F_g,h_g)
[F_w_N0, h_w_N0] = pdiff(F_w, h_w, ...
    [F_g zeros(length_Fg,m); ...
    zeros(m, n) eye(m); ...
    zeros(m, n) -eye(m)], ...
    [h_g; ...
    zeros(2*m,1)]);

% Simplify the constraints
term_poly = polytope(F_w_N0, h_w_N0);
[F_w_N, h_w_N] = double(term_poly);

disp('Terminal set polytope:');
term_poly

% x-theta constraints:
F_xTheta = F_w_N(:, 1:n);
F_theta = F_w_N(:,n+1:n+m);
f_xTheta = h_w_N;

%%
%==========================================================================
% Generate inequality constraints
%==========================================================================

length_Fw = size(F_w_N, 1);

Aineq = zeros((N-1)*length_Fx+N*length_Fu+length_Fw, N*m+m);
bineq = zeros((N-1)*length_Fx+N*length_Fu+length_Fw, 1);
b_crx = zeros((N-1)*length_Fx+N*length_Fu+length_Fw, n);

L_i = zeros(n, N*m);
KL_i = zeros(m, N*m);
disp('Generating constraints on inputs...');
d_i = zeros(n,1);
for ind = 1:N
    %disp(['u ind: ', num2str(ind)]);
    
    KL_i = K*L_i;
    KL_i(:, (ind-1)*m + (1:m)) = eye(m);
    
    Aineq((ind-1)*length_Fu + (1:length_Fu),1:N*m) = F_u*KL_i;
    bineq((ind-1)*length_Fu + (1:length_Fu)) = h_u - F_u*K*d_i;
    b_crx((ind-1)*length_Fu + (1:length_Fu),:) = -F_u*K*(A+B*K)^(ind-1);
    
    L_i = [(A+B*K)^(ind-1)*B L_i(:, 1:(N-1)*m)];
    d_i = (A+B*K)*d_i + d_0;
end

L_i = zeros(n, N*m);
disp('Generating constraints on states...');
d_i = d_0;
for ind = 1:N
    %disp(['x ind: ', num2str(ind)]);
    L_i = [(A+B*K)^(ind-1)*B L_i(:, 1:(N-1)*m)];
    
    if ind == 1
        disp('Generating terminal constraints on states...');
        Aineq(N*length_Fu + (1:length_Fw), :) = F_w_N*[L_i zeros(n,m); zeros(m,N*m) eye(m)];
        bineq(N*length_Fu + (1:length_Fw)) = h_w_N - F_w_N*[d_i; zeros(m,1)];
        b_crx(N*length_Fu + (1:length_Fw),:) = -F_w_N*[(A+B*K)^(ind); zeros(m,n)];
        
    else
        
        Aineq(length_Fw + N*length_Fu + (ind-2)*length_Fx + (1:length_Fx),1:N*m) = F_x*L_i;
        bineq(length_Fw + N*length_Fu + (ind-2)*length_Fx + (1:length_Fx)) = h_x - F_x*d_i;
        b_crx(length_Fw + N*length_Fu + (ind-2)*length_Fx + (1:length_Fx),:) = -F_x*(A+B*K)^(ind);
        
    end
    
    d_i = (A+B*K)*d_i + d_0;
end

ind = N;
L_i = [(A+B*K)^(ind-1)*B L_i(:, 1:(N-1)*m)];


CONSTRAINT_COUNT = length(bineq);