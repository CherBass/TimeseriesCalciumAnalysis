%Calcium signal analysis
%function [binaryImageLabelledResized, binaryImageLabelled, cellLocations] = CalciumSignalSegmentation()
%% read image
close all; clear all;
%Initialize
Plot = 0;
detector = 'SURF';
shiftCentroid = 1;
distThresh = 10;
cellSize = 50;
con = 4;

%I = double(imread(image));
%ITimeseries = double(imread(imageTimeseries));

%% Extract mean image and time series image
I = double(imread('AT61_A-001.tif'));
imgInfo = imfinfo('AT61_A_T-series-001.tif');
numLayers = length(imgInfo);

for time = 1:numLayers
    ITimeseries(:,:,time) = double(imread('AT61_A_T-series-001.tif', time));
end

if Plot == 1
    figure, imagesc(I); colormap(gray); title('original image'); 
    axis off;
end
sizeImage = size(I,1);
sizeITs = size(ITimeseries,1);

%% Laplacian of Gaussians convolution

[LoGImage, padSize] = LoGConv(I, Plot); %convolve image with LoG mask
LoGNorm = LoGImage / max((LoGImage(:)));

if strcmp(detector, 'SURF')
    %SURF keypoints
    SURFPoints = detectSURFFeatures(LoGNorm);
    SURFLocations = SURFPoints.Location;
    SURFLocations = SURFLocations - padSize(1);
    detectorLocations.SURF = SURFLocations;
    interestPoints = SURFLocations;
    
elseif strcmp(detector, 'harris')
    %Harris keypoints
    harrisPoints = detectHarrisFeatures(LoGNorm);
    harrisLocations = harrisPoints.Location;
    harrisLocations = harrisLocations - padSize(1);
    detectorLocations.harris = harrisLocations;
    interestPoints = harrisLocations;
    
elseif strcmp(detector, 'SIFT')
    %SIFT keypoints
    [SIFTPoints, SIFTFeatures] = vl_sift(single(LoGNorm));
    [~, indexFeatures] = sort(sum(SIFTFeatures,1), 'ascend');
    SIFTLocations = SIFTPoints(1:2,indexFeatures(1:100))';
    SIFTLocations = SIFTLocations - padSize(1);
    detectorLocations.SIFT = SIFTLocations;
    interestPoints = SIFTLocations;
end    

%check all points are positive
[row,~] = find(interestPoints < 1);
interestPoints(row,:) = [];
[row,~] = find(interestPoints > sizeImage);
interestPoints(row,:) = [];

cellLocations = interestPoints;
%% Plot interest points
if Plot==1
    figure; imagesc(I); colormap(gray); hold on;
    plot(interestPoints(:,1),interestPoints(:,2),'r+')
    title('Cell interest points');
    axis off;
end

%% Remove locations with low intensity
% 
% meanIntensity = mean(I(:));
% STDIntensity = std(double(I(:)));
% 
% for i = 1:length(interestPoints)
%     intensities(i) = I(round(interestPoints(i,1)),round(interestPoints(i,2)));
% end
% 
% [~,col] = find(intensities < (meanIntensity - STDIntensity));
% interestPoints(col,:) = [];
% 
% % Plot interest points
% if Plot==1
%     figure; imagesc(I); colormap(gray); hold on;
%     plot(interestPoints(:,1),interestPoints(:,2),'b+')
%     title('Cell interest points');
%     axis off;
% end
%% Shift centroids to local maximum

%shift interest points to their local max
%[cellLocations] = shiftCentroidsToLocalMax(cellLocations, I, shiftCentroid);

%% Discard close boutons
%remove boutons closer than distThresh. Bouton with the lower pixel
%intensity is removed

[cellLocations] = removeAllCloseBoutons(cellLocations, I, distThresh);
% Plot interest points
if Plot==1
    figure; imagesc(I); colormap(gray); hold on;
    plot(cellLocations(:,1),cellLocations(:,2),'g+')
    title('Cell interest points');
    axis off;
end

%% Extract bouton patches
%Extract the bouton patches using the bouton locations extracted
for n = 1:length(cellLocations)
    x1(n) = round(cellLocations(n,1) - round(cellSize/2));
    x2(n) = round(cellLocations(n,1) + round(cellSize/2));
    y1(n) = round(cellLocations(n,2) - round(cellSize/2));
    y2(n) = round(cellLocations(n,2) + round(cellSize/2));

    %Ensure indeces are within the image margins
    if x1(n) <= 0
        x1(n) = 1;
    end
    if y1(n) <= 0
        y1(n) = 1;
    end
    if x2(n) > sizeImage
        x2(n) = round(sizeImage);
    end
    if y2(n) > sizeImage
        y2(n) = round(sizeImage);
    end
end

[cellPatch] = extractBoutonPatch(cellLocations, cellSize, sizeImage, I, 0);

%create a binary image
binaryImage = zeros(sizeImage);

%% Segmentation
for n = 1:length(cellPatch)
    patch = cellPatch{n};
    maxPixelVal = max(patch(:));
    meanPixelVal = mean(patch(:));
    stdPixel = std(patch(:));
    thresh = meanPixelVal + stdPixel;
    BW = patch > thresh;
    
    %remove small regions
    BW2 = bwareaopen(BW,100,con);
    
    %dilate
    BW2 = bwmorph(BW2,'close',inf);  
    
    %remove all but 1 cells
    [BWLabelled, num] = bwlabel(BW2, con);
    if num > 1
        area = [];
        tempPatch = zeros([size(patch),num]);
        for j = 1:num
           tempPatch(:,:,j) = BWLabelled == j;
           area(j) = bwarea(tempPatch(:,:,j));
        end
    
    [~,index] = max(area);
    BW2 = tempPatch(:,:,index);
    end
    %cc = bwconncomp(BW); %not needed
    
    binaryImage(y1(n):y2(n),x1(n):x2(n)) = BW2;
    
    
    if Plot == 1
        figure, imagesc(patch); colormap(gray);
        title('Orignal patch');
        movegui('west');
        axis off;
        figure, imagesc(BW2); colormap(gray);
        title('Segmented Image');
        movegui('east');
        axis off;
        pause(1);
    end
end

binaryImage = bwmorph(binaryImage,'close',1); 
%[binaryImageLabelled, NumCells] = bwlabel(binaryImage, con);

%% Plot
I2 = imresize(I, [sizeITs sizeITs]);
binaryImage2 = imresize(binaryImage, [sizeITs sizeITs]);
[binaryImageLabelledResized, NumCells] = bwlabel(binaryImage2, con);

figure, imagesc(I2); colormap(gray);
title('Orignal image with segmented cells');
axis off;
hold on;

[B,L] = bwboundaries(binaryImage2,'noholes');
%imshow(label2rgb(L, @jet, [.5 .5 .5]))
for k = 1:length(B)
   boundary = B{k};
   plot(boundary(:,2), boundary(:,1), 'w', 'LineWidth', 2)
end

%% use binary mask to extract time series

figure;
for c = 1:NumCells
    mask = binaryImageLabelledResized == c; 
    %mask3D = repmat(mask,[1,1,numLayers]);
    %maskOnly = mask3D .* ITimeseries;
    for time = 1:numLayers
        temp = ITimeseries(:,:,time);
        trace(c,time) = mean(mean(temp(mask)));
    end    
end

subplot(2,1,1);
plot(1:1:800,trace(1,:));
subplot(2,1,2);
plot(1:1:800,trace(2,:));




%end