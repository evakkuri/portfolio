#!/usr/bin/env python3

"""
SOURCE FOR DATA AND ASSIGNMENT:
University of Helsinki, course Data Analysis with Python 2020
Link to course description: https://courses.helsinki.fi/fi/aycsm90004en/135221588

EXERCISE 4 (spam detection)
This exercise gives two points if solved correctly!

In the src folder there are two files: ham.txt.gz and spam.txt.gz. The files are
preprocessed versions of the files from
https://spamassassin.apache.org/old/publiccorpus/. There is one email per line.
The file ham.txt.gz contains emails that are non-spam, and, conversely, emails
in file spam.txt are spam. The email headers have been removed, except for the
subject line, and non-ascii characters have been deleted.

Write function spam_detection that does the following:

- Reads the lines from these files into arrays.
    - Use function open from gzip module, since the files are compressed.
    - From each file take only fraction of lines from the start of the file,
      where fraction is a parameter to spam_detection, and should be in the
      range [0.0, 1.0].

- Forms the combined feature matrix using CountVectorizer class’ fit_transform
  method.
    - The feature matrix should first have the rows for the ham dataset and then
      the rows for the spam dataset.
    - One row in the feature matrix corresponds to one email.
    - Use labels 0 for ham and 1 for spam

- Divides that feature matrix and the target label into training and test sets,
  using train_test_split.
    - Use 75% of the data for training.
    - Pass the random_state parameter from spam_detection to train_test_split.

- Trains a MultinomialNB model, and use it to predict the labels for the test
  set

The function should return a triple consisting of
* accuracy score of the prediction
* size of test sample
* number of misclassified sample points
"""

import gzip
from typing import List

import numpy as np
import sklearn
from sklearn.feature_extraction.text import CountVectorizer
from sklearn import metrics
from sklearn.model_selection import train_test_split
from sklearn.naive_bayes import MultinomialNB
from sklearn.pipeline import make_pipeline


def load_data(fraction: float) -> (List[str], List[str]):
    """
    Loads ham and spam datasets from gzip-compressed files given as part of the
    assignment.

    Parameters:
    - fraction (float): Used to determine the fraction of lines to return for
      both datasets counting from the beginning of the dataset

    Returns:
    - ham_data_fraction: Fraction of the full ham dataset counting from the
      beginning of the source data file
    - spam_data_fraction: Fraction of the full spam dataset counting from the
      beginning of the source data file
    """

    with gzip.open("src/ham.txt.gz") as f:
        ham_data = f.readlines()

    with gzip.open("src/spam.txt.gz") as f:
        spam_data = f.readlines()

    if fraction > 1.0:
        fraction = 1.0

    if fraction < 0.0:
        fraction = 0.0

    # Constrict to length determined by fraction param
    ham_data_fraction = ham_data[:int(len(ham_data) * fraction)]
    spam_data_fraction = spam_data[:int(len(spam_data) * fraction)]

    return ham_data_fraction, spam_data_fraction


def get_features_and_labels(ham_list: List[str], spam_list: List[str]) \
        -> (np.array, np.array):
    """
    Create numpy arrays for features and labels by vectorizing and combining
    the ham and spam datasets

    Parameters:
    - ham_list: list of ham email contents as strings
    - spam_list: list of spam email contents as strings

    Returns:
    - features: Word count vectorization of the combined ham and spam datasets
        as Numpy array
    - labels: Corresponding labels for each row in features, label 0 for ham and
        1 for span
    """
    vec = CountVectorizer()

    all_list = ham_list + spam_list
    ham_labels = np.zeros(len(ham_list))
    spam_labels = np.ones(len(spam_list))

    features = vec.fit_transform(all_list).toarray()
    labels = np.concatenate((ham_labels, spam_labels))

    return features, labels


def spam_detection(random_state: int = 0, fraction: float = 1.0) \
        -> (float, int, int):
    """
    Trains a multinomial Naive Bayes model to detect spam emails.

    Two alternative ways of constructing the model are included. Method 1 does
    vectorization separately from model training, method 2 uses a single
    scikit-learn pipeline for both vectorization and model training. Curiously,
    method 2 does better when fraction=0.1, but slightly worse when using the
    full dataset. There are some commented lines for analysis of the difference,
    but nothing conclusive.

    Parameters:
    - random_state: Seed for random values, used for deterministic
        train-test split
    - fraction: Fraction of spam and ham datasets to use in model training.
        Used to limit the dataset size for resource constrained infrastructure

    Returns:
    - acc_1: Accuracy of model trained with method 1 described above
    - labels_2_test_size: Size of test dataset with method 1
    - misclassified_1: Number of misclassified emails with method 1
    """

    ham_data, spam_data = load_data(fraction)

    # METHOD 1: With count vectorization separately
    # This returns the result expected by tests
    features_1, labels_1 = get_features_and_labels(ham_data, spam_data)

    features_1_train, features_1_test, labels_1_train, labels_1_test = \
        train_test_split(features_1, labels_1, train_size=0.75,
                         random_state=random_state)

    model_1 = MultinomialNB()
    model_1.fit(features_1_train, labels_1_train)
    labels_1_pred = model_1.predict(features_1_test)

    acc_1 = metrics.accuracy_score(labels_1_pred, labels_1_test)
    labels_1_test_size = len(labels_1_test)
    misclassified_1 = labels_1_pred != labels_1_test

    print(acc_1, labels_1_test_size, misclassified_1.sum())

    # METHOD 2: With count vectorization and MultinomialNB in one pipeline
    ham_labels = [0 for mail in ham_data]
    spam_labels = [1 for mail in spam_data]

    # This returns a better result than expected by the tests
    data_2 = ham_data + spam_data
    labels_2 = ham_labels + spam_labels

    data_2_train, data_2_test, labels_2_train, labels_2_test = \
        train_test_split(data_2, labels_2, train_size=0.75,
                         random_state=random_state)
    model = make_pipeline(CountVectorizer(), MultinomialNB())

    model.fit(data_2_train, labels_2_train)
    labels_2_pred = model.predict(data_2_test)
    labels_2_test = np.array(labels_2_test)

    acc_2 = metrics.accuracy_score(labels_2_pred, labels_2_test)
    labels_2_test_size = len(labels_2_test)
    misclassified_2 = labels_2_pred != labels_2_test

    print(acc_2, labels_2_test_size, misclassified_2.sum())

    # Analysis of difference
    miscl_data_1_idx = [i for i in range(
        len(data_2_test)) if list(misclassified_1)[i]]
    miscl_data_2_idx = [i for i in range(
        len(data_2_test)) if list(misclassified_2)[i]]
    difference = list(set(miscl_data_1_idx) - set(miscl_data_2_idx))

    print(miscl_data_1_idx)
    print(miscl_data_2_idx)
    print(difference)

    for msg_idx in difference:
        print(
            data_2[msg_idx],
            int(labels_1_pred[msg_idx]),
            labels_2_pred[msg_idx],
            int(labels_1_test[msg_idx]),
            labels_2_test[msg_idx]
        )

    return acc_1, labels_1_test_size, misclassified_1.sum()


def main():
    """
    Main function, runs spam classification training.
    """

    accuracy, total, misclassified = spam_detection(
        random_state=5, fraction=1.0)
    print("Accuracy score:", accuracy)
    print(f"{misclassified} messages miclassified out of {total}")


if __name__ == "__main__":
    main()
