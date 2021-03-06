function Y = zscorebigmem(Y, chunk_siz)
% zscorebigmem: z-score X to the last dimention 
%   1DxT or 2DxT or 3DxT matrices
%
% Usage:
%   Y = zscorebigmem(Y, chunk_siz)
%
% Args:
%   Y: 1DxT or 2DxT or 3DxT matrix
%   chunk_siz: chunk size to run at a time in dimension 1
%
% Notes:
% for std normalozation I used a equivalent to std(A, 1)

if ~exist('chunk_siz', 'var') || isempty(chunk_siz)
    chunk_siz = 5e3;
end

% flip dimension if a vertical vector is provided
if length(size(Y)) <= 2 && ...
    size(Y, 2) == 1
    Y = Y';
end

Y = double(Y);
Y = centerbigmem(Y, chunk_siz);
Y = sdnormbigmem(Y, chunk_siz);

end
